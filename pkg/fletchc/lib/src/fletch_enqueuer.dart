// Copyright (c) 2015, the Fletch project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

library fletchc.fletch_enqueuer;

import 'dart:collection' show Queue;

import 'package:compiler/src/dart2jslib.dart' show
    CodegenEnqueuer,
    CodegenWorkItem,
    Compiler,
    CompilerTask,
    EnqueueTask,
    ItemCompilationContextCreator,
    QueueFilter,
    Registry,
    ResolutionEnqueuer,
    WorkItem,
    WorldImpact;

import 'package:compiler/src/universe/universe.dart' show
    Universe,
    UniverseSelector;

import 'package:compiler/src/dart_types.dart' show
    DartType,
    InterfaceType;

import 'package:compiler/src/elements/elements.dart' show
    ClassElement,
    ConstructorElement,
    Element,
    FunctionElement,
    LibraryElement,
    LocalFunctionElement,
    TypedElement;

import 'fletch_compiler_implementation.dart' show
    FletchCompilerImplementation;

part 'enqueuer_mixin.dart';

const bool useCustomEnqueuer = const bool.fromEnvironment(
    "fletchc.use-custom-enqueuer", defaultValue: false);

CodegenEnqueuer makeCodegenEnqueuer(FletchCompilerImplementation compiler) {
  ItemCompilationContextCreator itemCompilationContextCreator =
      compiler.backend.createItemCompilationContext;
  return useCustomEnqueuer
      ? new FletchEnqueuer(compiler, itemCompilationContextCreator)
      : new CodegenEnqueuer(compiler, itemCompilationContextCreator);
}

/// Custom enqueuer for Fletch.
class FletchEnqueueTask extends CompilerTask implements EnqueueTask {
  final ResolutionEnqueuer resolution;

  // TODO(ahe): Should be typed [FletchEnqueuer].
  final CodegenEnqueuer codegen;

  FletchEnqueueTask(FletchCompilerImplementation compiler)
    : resolution = new ResolutionEnqueuer(
          compiler, compiler.backend.createItemCompilationContext),
      codegen = makeCodegenEnqueuer(compiler),
      super(compiler) {
    codegen.task = this;
    resolution.task = this;

    codegen.nativeEnqueuer = compiler.backend.nativeCodegenEnqueuer(codegen);

    resolution.nativeEnqueuer =
        compiler.backend.nativeResolutionEnqueuer(resolution);
  }

  String get name => 'Fletch enqueue';

  void forgetElement(Element element) {
    resolution.forgetElement(element);
    codegen.forgetElement(element);
  }
}

class FletchEnqueuer extends EnqueuerMixin implements CodegenEnqueuer {
  final ItemCompilationContextCreator itemCompilationContextCreator;

  final FletchCompilerImplementation compiler;

  final Map generatedCode = new Map();

  bool queueIsClosed = false;

  bool hasEnqueuedReflectiveElements = false;

  bool hasEnqueuedReflectiveStaticFields = false;

  EnqueueTask task;

  // TODO(ahe): Get rid of this?
  var nativeEnqueuer;

  final Universe universe = new Universe();

  final Set<Element> newlyEnqueuedElements;

  final Set<UniverseSelector> newlySeenSelectors;

  final Set<ClassElement> _instantiatedClasses = new Set<ClassElement>();

  final Queue<ClassElement> _pendingInstantiatedClasses =
      new Queue<ClassElement>();

  final Set<Element> _enqueuedElements = new Set<Element>();

  final Queue<Element> _pendingEnqueuedElements = new Queue<Element>();

  final Set<UniverseSelector> _enqueuedSelectors = new Set<UniverseSelector>();

  final Queue<UniverseSelector> _pendingSelectors =
      new Queue<UniverseSelector>();

  final Set<Element> _processedElements = new Set<Element>();

  FletchEnqueuer(
      FletchCompilerImplementation compiler,
      this.itemCompilationContextCreator)
      : compiler = compiler,
        newlyEnqueuedElements = compiler.cacheStrategy.newSet(),
        newlySeenSelectors = compiler.cacheStrategy.newSet();


  bool get queueIsEmpty => _pendingEnqueuedElements.isEmpty;

  bool get isResolutionQueue => false;

  QueueFilter get filter => compiler.enqueuerFilter;

  void forgetElement(Element element) {
    // TODO(ahe): Implement
    print("FletchEnqueuer.forgetElement isn't implemented");
  }

  void registerInstantiatedType(
      InterfaceType type,
      Registry registry,
      {bool mirrorUsage: false}) {
    ClassElement cls = type.element.declaration;
    if (_instantiatedClasses.add(cls)) {
      _pendingInstantiatedClasses.addLast(cls);
    }
  }

  void registerStaticUse(Element element) {
    _enqueueElement(element);
  }

  void addToWorkList(Element element) {
    _enqueueElement(element);
  }

  void forEach(void f(WorkItem work)) {
    do {
      do {
        while (!queueIsEmpty) {
          Element element = _pendingEnqueuedElements.removeFirst();
          if (element.isField) continue;
          CodegenWorkItem workItem = new CodegenWorkItem(
              compiler, element, itemCompilationContextCreator());
          filter.processWorkItem(f, workItem);
          _processedElements.add(element);
        }
        _enqueueInstanceMethods();
      } while (!queueIsEmpty);
      // TODO(ahe): Pass recentClasses?
      compiler.backend.onQueueEmpty(this, null);
    } while (!queueIsEmpty);
  }

  bool checkNoEnqueuedInvokedInstanceMethods() {
    // TODO(ahe): Implement
    return true;
  }

  void logSummary(log(message)) {
    log('Compiled ${generatedCode.length} methods.');
    nativeEnqueuer.logSummary(log);
  }

  bool isProcessed(Element member) => _processedElements.contains(member);

  void registerDynamicInvocation(UniverseSelector selector) {
    _enqueueDynamicSelector(selector);
  }

  void applyImpact(Element element, WorldImpact worldImpact) {
    // TODO(ahe): Copied from Enqueuer.
    worldImpact.dynamicInvocations.forEach(registerDynamicInvocation);
    worldImpact.dynamicGetters.forEach(registerDynamicGetter);
    worldImpact.dynamicSetters.forEach(registerDynamicSetter);
    worldImpact.staticUses.forEach(registerStaticUse);
    worldImpact.checkedTypes.forEach(registerIsCheck);
    worldImpact.closurizedFunctions.forEach(registerGetOfStaticFunction);
  }

  void registerDynamicGetter(UniverseSelector selector) {
    _enqueueDynamicSelector(selector);
  }

  void registerDynamicSetter(UniverseSelector selector) {
    _enqueueDynamicSelector(selector);
  }

  void _enqueueElement(Element element) {
    if (_enqueuedElements.add(element)) {
      _pendingEnqueuedElements.addLast(element);
      newlyEnqueuedElements.add(element);
    }
  }

  Element _enqueueApplicableMembers(
      ClassElement cls,
      UniverseSelector selector) {
    Element member = cls.lookupByName(selector.selector.memberName);
    if (member != null && task.resolution.isProcessed(member)) {
      // TODO(ahe): Check if selector applies; Don't consult resolution.
      _enqueueElement(member);
    }
  }

  void _enqueueInstanceMethods() {
    while (!_pendingInstantiatedClasses.isEmpty) {
      ClassElement cls = _pendingInstantiatedClasses.removeFirst();
      for (UniverseSelector selector in _enqueuedSelectors) {
        // TODO(ahe): As we iterate over _enqueuedSelectors, we may end up
        // processing calling _enqueueApplicableMembers twice for newly
        // instantiated classes. Once here, and then once more in the while
        // loop below.
        _enqueueApplicableMembers(cls, selector);
      }
    }
    while (!_pendingSelectors.isEmpty) {
      UniverseSelector selector = _pendingSelectors.removeFirst();
      for (ClassElement cls in _instantiatedClasses) {
        _enqueueApplicableMembers(cls, selector);
      }
    }
  }

  void _enqueueDynamicSelector(UniverseSelector selector) {
    if (_enqueuedSelectors.add(selector)) {
      _pendingSelectors.add(selector);
      newlySeenSelectors.add(selector);
    }
  }
}

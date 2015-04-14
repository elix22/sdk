// Copyright (c) 2015, the Fletch project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

library fletch.session;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'bytecodes.dart';
import 'commands.dart';
import 'compiler.dart' show FletchCompiler;
import 'src/debug_info.dart';

part 'command_reader.dart';
part 'input_handler.dart';
part 'stack_trace.dart';

class Breakpoint {
  final String methodName;
  final int bytecodeIndex;
  final int id;
  Breakpoint(this.methodName, this.bytecodeIndex, this.id);
  String toString() => "$id: $methodName@$bytecodeIndex";
}

class Session {
  final Socket vmSocket;
  final FletchCompiler compiler;
  final Map<int, Breakpoint> breakpoints = new Map();

  StreamIterator<Command> vmCommands;
  StackTrace currentStackTrace;
  int currentFrame;
  SourceLocation currentLocation;

  Session(this.vmSocket, this.compiler);

  void writeSnapshot(String snapshotPath) {
    new WriteSnapshot(snapshotPath).addTo(vmSocket);
    vmSocket.drain();
    quit();
  }

  void run() {
    const ProcessSpawnForMain().addTo(vmSocket);
    const ProcessRun().addTo(vmSocket);
    vmSocket.drain();
    quit();
  }

  Future debug() async {
    vmCommands = new CommandReader(vmSocket).iterator;
    const ProcessSpawnForMain().addTo(vmSocket);
    await new InputHandler(this).run();
  }

  Future nextVmCommand() async {
    var hasNext = await vmCommands.moveNext();
    assert(hasNext);
    return vmCommands.current;
  }

  Future handleProcessStop() async {
    currentStackTrace = null;
    currentFrame = 0;
    Command response = await nextVmCommand();
    switch (response.code) {
      case CommandCode.UncaughtException:
        await backtrace();
        const ForceTermination().addTo(vmSocket);
        break;
      case CommandCode.ProcessTerminate:
        print('### process terminated');
        quit();
        exit(0);
        break;
      default:
        assert(response.code == CommandCode.ProcessBreakpoint);
        await getStackTrace();
        break;
    }
  }

  Future debugRun() async {
    const ProcessRun().addTo(vmSocket);
    await handleProcessStop();
  }

  // TODO(ager): Implement support for setting breakpoints based on source
  // position.
  Future setBreakpoint({String methodName, int bytecodeIndex}) async {
    Iterable<int> functionIds = compiler.lookupFunctionIdsByName(methodName);
    for (int id in functionIds) {
      new PushFromMap(MapId.methods, id).addTo(vmSocket);
      new ProcessSetBreakpoint(bytecodeIndex).addTo(vmSocket);
      ProcessSetBreakpoint response = await nextVmCommand();
      int breakpointId = response.value;
      var breakpoint = new Breakpoint(methodName, bytecodeIndex, breakpointId);
      breakpoints[breakpointId] = breakpoint;
      print("breakpoint set: $breakpoint");
    }
  }

  Future deleteBreakpoint(int id) async {
    if (!breakpoints.containsKey(id)) {
      print("### invalid breakpoint id: $id");
      return;
    }
    new ProcessDeleteBreakpoint(id).addTo(vmSocket);
    ProcessDeleteBreakpoint response = await nextVmCommand();
    assert(response.id == id);
    print("deleted breakpoint: ${breakpoints[id]}");
    breakpoints.remove(id);
  }

  void listBreakpoints() {
    if (breakpoints.isEmpty) {
      print('No breakpoints.');
      return;
    }
    print("Breakpoints:");
    for (var bp in breakpoints.values) {
      print(bp);
    }
  }

  Future step() async {
    SourceLocation previous = currentLocation;
    do {
      await stepBytecode();
    } while (currentLocation == null || currentLocation == previous);
  }

  Future stepOver() async {
    SourceLocation previous = currentLocation;
    do {
      await stepOverBytecode();
    } while (currentLocation == null || currentLocation == previous);
  }

  Future stepBytecode() async {
    const ProcessStep().addTo(vmSocket);
    await handleProcessStop();
  }

  Future stepOverBytecode() async {
    const ProcessStepOver().addTo(vmSocket);
    await handleProcessStop();
  }

  Future cont() async {
    const ProcessContinue().addTo(vmSocket);
    await handleProcessStop();
  }

  void list() {
    if (currentStackTrace == null) {
      print("### no stack trace");
      return;
    }
    currentStackTrace.list(compiler, currentFrame);
  }

  void disasm() {
    if (currentStackTrace == null) {
      print("### no stack trace");
      return;
    }
    currentStackTrace.disasm(compiler, currentFrame);
  }

  void selectFrame(int frame) {
    if (currentStackTrace == null ||
        frame >= currentStackTrace.stackFrames.length) {
      print('### invalid frame number $frame');
      return;
    }
    currentFrame = frame;
  }

  Future getStackTrace() async {
    if (currentStackTrace == null) {
      const ProcessBacktrace(0).addTo(vmSocket);
      ProcessBacktrace backtraceResponse = await nextVmCommand();
      var frames = backtraceResponse.frames;
      currentStackTrace = new StackTrace(frames);
      for (int i = 0; i < currentStackTrace.frames; ++i) {
        new MapLookup(MapId.methods).addTo(vmSocket);
        const Drop(1).addTo(vmSocket);
        const PopInteger().addTo(vmSocket);
        var objectIdCommand = await nextVmCommand();
        var functionId = objectIdCommand.id;
        var integerCommand = await nextVmCommand();
        var bcp = integerCommand.value;
        currentStackTrace.addFrame(compiler, new StackFrame(functionId, bcp));
      }
      currentLocation = currentStackTrace.sourceLocation(compiler);
    }
  }

  Future backtrace() async {
    await getStackTrace();
    currentStackTrace.write(compiler, currentFrame);
  }

  void quit() {
    vmSocket.close();
  }
}

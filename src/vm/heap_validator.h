// Copyright (c) 2015, the Dartino project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

#ifndef SRC_VM_HEAP_VALIDATOR_H_
#define SRC_VM_HEAP_VALIDATOR_H_

#include "src/vm/heap.h"
#include "src/vm/scheduler.h"

namespace dartino {

#ifdef DEBUG
// We don't normally include the heap validation code in release builds, but
// you can edit these lines if you need it.
#define SUPPORT_HEAP_VALIDATION
#endif

class SharedHeap;

// Validates that all pointers it gets called with lie inside certain spaces -
// depending on [process_heap], [program_heap].
class HeapPointerValidator : public PointerVisitor {
 public:
  HeapPointerValidator(OneSpaceHeap* program_heap, TwoSpaceHeap* process_heap)
      : program_heap_(program_heap), process_heap_(process_heap) {}
  virtual ~HeapPointerValidator() {}

  virtual void VisitBlock(Object** start, Object** end);

 private:
  void ValidatePointer(Object* object);

  OneSpaceHeap* program_heap_;
  TwoSpaceHeap* process_heap_;
};

// Validates that all pointers it gets called with lie inside the program heap.
class ProgramHeapPointerValidator : public HeapPointerValidator {
 public:
  explicit ProgramHeapPointerValidator(OneSpaceHeap* program_heap)
      : HeapPointerValidator(program_heap, NULL) {}
  virtual ~ProgramHeapPointerValidator() {}
};

// Traverses roots and queues of a process and makes sure the pointers
// inside them are valid.
class ProcessRootValidatorVisitor : public ProcessVisitor {
 public:
  explicit ProcessRootValidatorVisitor(OneSpaceHeap* program_heap)
      : program_heap_(program_heap) {}
  virtual ~ProcessRootValidatorVisitor() {}

  virtual void VisitProcess(Process* process);

 private:
  OneSpaceHeap* program_heap_;
};

}  // namespace dartino

#endif  // SRC_VM_HEAP_VALIDATOR_H_

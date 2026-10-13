//
//  Autoreleasepool.swift
//  GoDFoundation
//
//  `autoreleasepool` comes from the Objective-C runtime, so it only exists on
//  Apple platforms. Elsewhere there are no autoreleased objects: a `Data` made
//  inside the loop body is released by ARC when the iteration's scope ends,
//  which is exactly what the pools are there to force on Darwin. Running the
//  body directly is therefore the faithful equivalent, not a workaround.
//

#if !canImport(ObjectiveC)
@inlinable
func autoreleasepool<Result>(invoking body: () throws -> Result) rethrows -> Result {
    try body()
}
#endif

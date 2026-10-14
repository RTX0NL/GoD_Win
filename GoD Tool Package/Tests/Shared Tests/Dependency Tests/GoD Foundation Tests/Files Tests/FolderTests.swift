//
//  FolderTests.swift
//  
//
//  Created by Stars Momodu on 31/05/2022.
//

import Foundation
import GoDFoundation
import XCTest

class GoDFolderTests: XCTestCase {

    /// A folder path in a config that `Folder.init` can't hold used to trap
    /// and take the process down, the MCP server included. Decoding must
    /// fail with an error instead.
    func testDecodingAnInvalidFolderPathThrows() {
        for bad in ["Engines", "Build/Unpacked", ""] {
            XCTAssertThrowsError(
                try JSONDecoder().decode(Folder.self, from: Data("\"\(bad)\"".utf8)), bad
            ) { error in
                guard case DecodingError.dataCorrupted(let context) = error else {
                    return XCTFail("\(bad): expected dataCorrupted, got \(error)")
                }
                XCTAssertTrue(context.debugDescription.contains("\"\(bad)\""), context.debugDescription)
            }
        }
    }

    func testDecodingValidFolderPathsStillWorks() throws {
        for good in ["/Assets", "./Build", "../Engines", ".", "..", "/"] {
            XCTAssertNoThrow(try JSONDecoder().decode(Folder.self, from: Data("\"\(good)\"".utf8)), good)
        }
    }

    func testIsValidPathMatchesInit() {
        XCTAssertTrue(Folder.isValidPath("/a/"))
        XCTAssertTrue(Folder.isValidPath("./a"))
        XCTAssertFalse(Folder.isValidPath("a/b"))
        XCTAssertFalse(Folder.isValidPath(""))
    }

    func testInit() {
        let folder = Folder("/initTest")
        XCTAssertEqual(folder.path, "/initTest")

        let folder2 = Folder("/initTest/test2")
        XCTAssertEqual(folder2.path, "/initTest/test2")

        // Trailing separator is stripped
        let folder3 = Folder("/initTest/separator test/")
        XCTAssertEqual(folder3.path, "/initTest/separator test")

        // Relative paths are preserved
        let folder4 = Folder("./relative")
        XCTAssertEqual(folder4.path, "./relative")

        let folder5 = Folder("../parent")
        XCTAssertEqual(folder5.path, "../parent")

        // Current directory
        let folder6 = Folder(".")
        XCTAssertEqual(folder6.path, ".")

        let folder7 = Folder("..")
        XCTAssertEqual(folder7.path, "..")
    }

    func testInitLiteral() {
        let folder: Folder = "/literalTest"
        XCTAssertEqual(folder.path, "/literalTest")

        let folder2: Folder = "/literalTest/test2"
        XCTAssertEqual(folder2.path, "/literalTest/test2")

        let folder3: Folder = "/literalTest/separator test/"
        XCTAssertEqual(folder3.path, "/literalTest/separator test")
    }
    
    func testFolderName() {
        let sut = Folder("/root/folder/sub folder")
        XCTAssertEqual(sut.folderName, "sub folder")
        
        let sut2 = Folder("/root")
        XCTAssertEqual(sut2.folderName, "root")
    }
    
    func testFileVar() {
        let folder = Folder("/testFolderTemp/sub folder")
        let sut = folder.file("file name.ext")
        XCTAssertEqual(sut.path, "/testFolderTemp/sub folder/file name.ext")
        
        let sut2 = folder.file("directory/file name.ext")
        XCTAssertEqual(sut2.path, "/testFolderTemp/sub folder/directory/file name.ext")
        
        let sut3 = folder.file("directory/file name.ext")
        XCTAssertEqual(sut3.path, "/testFolderTemp/sub folder/directory/file name.ext")
    }
    
    func testFolderVar() {
        let folder = Folder("/testFolderTemp/sub folder")
        let sut = folder.folder("folder name")
        XCTAssertEqual(sut.path, "/testFolderTemp/sub folder/folder name")
        
        let sut2 = folder.folder("directory/folder name")
        XCTAssertEqual(sut2.path, "/testFolderTemp/sub folder/directory/folder name")
        
        let sut3 = folder.folder("directory/folder name")
        XCTAssertEqual(sut3.path, "/testFolderTemp/sub folder/directory/folder name")
    }
    
    func testParent() {
        let sut = Folder("/root/path/sub path/directory")
        let parent = sut.parentFolder
        XCTAssertEqual(parent?.path, "/root/path/sub path")
        let grandParent = parent?.parentFolder
        XCTAssertEqual(grandParent?.path, "/root/path")
        let greatParent = grandParent?.parentFolder
        XCTAssertEqual(greatParent?.path, "/root")
        let greatParent2 = greatParent?.parentFolder
        XCTAssertEqual(greatParent2?.path, "/")
        let greatParent3 = greatParent2?.parentFolder
        XCTAssertNil(greatParent3?.path)
    }
}

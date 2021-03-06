import Foundation
import DI2Support

/// Array of command line arguments given by the user
let CMDLineArgs = Array(CommandLine.arguments.dropFirst())

/// DMGs specified by the user to attach
let DMGSInputted = CMDLineArgs.map {
    // Resolve the symlinks first
    resolveSymlinks(ofPath: $0)
}.filter {
    // Then filter by DMG files that exist only
    NSString(string: $0).pathExtension == "dmg" && fm.fileExists(atPath: $0)
}

/// The `disk` or `/dev/disk` directories inputted by the user
let DevDiskPathsInputted = CMDLineArgs.filter {
    $0.contains("disk") && NSString(string: $0).pathExtension != "dmg"
}

let shouldDetach = CMDLineArgs.contains("--detach") || CMDLineArgs.contains("-d")
let shouldAttach = CMDLineArgs.contains("--attach") || CMDLineArgs.contains("-a")
let shouldPrintImageURL = CMDLineArgs.contains("--image-url") || CMDLineArgs.contains("-i")


if CMDLineArgs.isEmpty || CMDLineArgs.contains("--help") || CMDLineArgs.contains("-h") {
    print(helpMessage)
    exit(0)
}

// Support for --image-url / -i
if shouldPrintImageURL {
    for var diskPath in DevDiskPathsInputted {
        if !diskPath.hasPrefix("/dev/") {
            diskPath.insert(contentsOf: "/dev/", at: diskPath.startIndex)
        }
        
        do {
            let diskURL = try getImageURLOfDisk(atPath: diskPath)
            print("Original Image URL of \(diskPath): \(diskURL?.path ?? "Unknown Path")")
        } catch {
            print("Error while getting original Image URL of \(diskPath): \(error.localizedDescription)")
        }
        
    }
}

if shouldDetach {
    guard !DevDiskPathsInputted.isEmpty else {
        fatalError("User used --detach / -d however did not specify a disk to detach.")
    }
    
    for var diskName in DevDiskPathsInputted {
        if !diskName.hasPrefix("/dev/") {
            diskName.insert(contentsOf: "/dev/", at: diskName.startIndex)
        }
        detachDisk(diskPath: diskName) { didDetach, errorEncountered in
            guard didDetach, errorEncountered == nil else {
                print("Error encountered with ejecting \(diskName): \(errorEncountered ?? "Unknown Error")")
                exit(EXIT_FAILURE)
            }
            
            print("Detached \(diskName)")
        }
    }
}

if shouldAttach {
    guard !DMGSInputted.isEmpty else {
        fatalError("User used --attach / -a however did not specify a DMG to attach.")
    }
    
    let shouldAutoMount = CMDLineArgs.contains("--auto-mount") || CMDLineArgs.contains("-m")
    
    let shouldPrintRegEntryID = CMDLineArgs.contains("--reg-entry-id") || CMDLineArgs.contains("-r")
    let shouldVerify = CMDLineArgs.contains("--verify") || CMDLineArgs.contains("-v")
    
    for DMG in DMGSInputted {
        let Handler: DIDeviceHandle?
        let fileMode = returnFileModeFromCMDLine()
        
        do {
            Handler = try AttachDMG(
                atPath: DMG,
                doAutoMount: shouldAutoMount,
                fileMode: fileMode
            )
        } catch {
            Handler = nil
            print("Error encountered while attaching DMG \(DMG): \(error.localizedDescription)")
            exit(EXIT_FAILURE)
        }
        
        guard let Handler = Handler, let BSDName = Handler.bsdName else {
            print("Attached DMG However couldn't get info of attached disk.")
            exit(EXIT_FAILURE)
        }
        
        if shouldVerify {
            guard let verifyParams = try? DIVerifyParams(url: URL(fileURLWithPath: "/dev/\(BSDName)")) else {
                print("Couldn't verify that DMG Was attached Successfully")
                exit(EXIT_FAILURE)
            }
            
            let verifyStatus = verifyParams.verifyWithError(nil)
            guard verifyStatus else {
                print("DMG was not attached successfully.")
                exit(EXIT_FAILURE)
            }
            
            print("Verified that DMG \(DMG) was successfully attached")
        }
        
        print("Attached \(DMG) as \(BSDName)")
        
        if shouldPrintRegEntryID {
            print("\(BSDName) RegEntryID: \(Handler.regEntryID)")
        }
    }
}

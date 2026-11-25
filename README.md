# Drive Download Merge

When you download a big folder from Google Drive, Google splits it into several zip files. Each zip has part of your folders in it. After you unzip them you end up with a pile of folders named `drive-download-...` that all look the same, with your files scattered across them.

This script puts everything back together into one folder called `Merged`, laid out the way it was in Google Drive.

**It never overwrites or deletes anything.**

- If two zips have the exact same file, it keeps one and tells you about the other.
- If two zips have different files with the same name, it keeps both. The second one gets a name like `photo (from 003).jpg`.
- It writes a log of every file so you can see where each one went.
- It does a practice run first and asks before it changes anything.

Works on Windows 10 and 11. No installs needed.

---

## How to use it

### 1. Put all the zips in one folder

Make a new folder with a short name close to the top of a drive, like `D:\drive` or `C:\drive`. Move all of the Google Drive zip files into it.

> Short folder names matter. Windows has trouble with very long file paths, and Google Drive folders can go deep.

### 2. Unzip each one

For each zip file:

1. Right-click the zip and choose **Extract All...**
2. Leave the suggested folder name as is and click **Extract**.

When you're done you should have one folder for every zip. If Google gave you 8 zips, you should see 8 `drive-download-...` folders.

Once they're all extracted, move the zip files somewhere else for safekeeping. Don't delete them until you've checked the result.

### 3. Download the script

1. Click [**Merge-DriveChunks.ps1**](Merge-DriveChunks.ps1) in the file list above.
2. Click the **Download raw file** button (the down arrow near the top right of the file).
3. Save it into the same folder as your `drive-download-...` folders.

Your folder should now look something like this.

```
D:\drive
  drive-download-20261125T035301Z-1-001
  drive-download-20261125T035301Z-1-002
  drive-download-20261125T035301Z-1-003
  ...
  Merge-DriveChunks.ps1
```

### 4. Run it

Right-click **Merge-DriveChunks.ps1** and choose **Run with PowerShell**.

On Windows 11, if you don't see that option, click **Show more options** first.

A blue or black window opens. The script lists the folders it found, scans your files, and does a practice run. **Nothing changes during the practice run.** On a big download the scan can take a few minutes with nothing new on screen. That's normal.

### 5. Pick Move or Copy

When the practice run finishes, the window shows a short summary and asks you to choose.

| Type | What happens | When to pick it |
| --- | --- | --- |
| **M** | Moves your files into `Merged` | Most people. It's fast and needs no extra disk space. |
| **C** | Copies your files into `Merged` and leaves the originals alone | You have plenty of free space and want the originals untouched. |
| **Enter** | Quits without changing anything | You want to look at the practice run log first. |

Type your choice and press **Enter**. When it's done you'll see **Every file is accounted for**. Press **Enter** to close the window.

### 6. Check the result

Open the new `Merged` folder and look around. Everything should be there in its original folders.

The script also leaves a log file next to it named like `merge-log-20261125-221500-move.csv`. Open it in Excel and look at the **Status** column.

| Status | Meaning | Do you need to do anything? |
| --- | --- | --- |
| New | The file was moved or copied into `Merged` | No |
| Duplicate | An identical copy was already in `Merged`, so this one was skipped | No |
| Renamed | Two different files had the same name. Both were kept, and this one got `(from 00X)` added to its name | Take a look and keep the one you want |
| FAILED | Something went wrong with this file | Yes. Don't delete anything. See Troubleshooting |

### 7. Clean up

Once you're happy with `Merged`, you can delete the `drive-download-...` folders. If you picked Move, anything still in them is an identical copy of a file that's already in `Merged`.

Keep the original zip files for a little while longer in case you notice something missing later.

---

## Troubleshooting

**The window opens and closes right away.**
Open the folder in File Explorer, click the address bar, type `powershell`, and press Enter. In the window that opens, paste this and press Enter.

```powershell
powershell -ExecutionPolicy Bypass -File .\Merge-DriveChunks.ps1
```

You'll see the same steps, and any error message will stay on screen.

**It says some zip files have not been extracted yet.**
The script found a zip with no matching folder next to it. Extract it (step 2), or move it out of the folder if you already extracted it somewhere else.

**It warns that folder numbers look like they're missing.**
The zips are numbered 001, 002, 003 and so on. If one number is missing, a zip probably didn't download or didn't get extracted. Go back to Google Drive and download it again.

**It seems stuck.**
It's probably still scanning. Open Task Manager (Ctrl + Shift + Esc), go to the **Performance** tab, and click your drive. If **Active time** is high, it's working.

**I need to stop it.**
Close the window. It's safe to stop at any point and run it again. Files that were already moved stay in `Merged`, and the next run picks up the rest.

**Some files say FAILED.**
The most common cause is a file path that's too long for Windows. Move everything to a shorter folder name (like `C:\d`) and run it again. Files that already made it into `Merged` won't be touched again.

**Extract All gives an error about a path being too long.**
Same fix. Use a shorter folder name close to the top of the drive.

---

## For command line users

Run it with options to skip the questions.

```powershell
.\Merge-DriveChunks.ps1                      # practice run, then asks Move / Copy / Quit
.\Merge-DriveChunks.ps1 -Move                # move with no questions
.\Merge-DriveChunks.ps1 -Copy                # copy with no questions
.\Merge-DriveChunks.ps1 -Root 'E:\export'    # chunk folders are somewhere else
```

Running it with any option turns off the questions and the "Press Enter to close" pause. Running it with only `-Root` or `-Pattern` does a practice run and stops.

| Option | Default | What it does |
| --- | --- | --- |
| `-Root` | The script's folder | Folder that holds the extracted chunk folders |
| `-Destination` | `<Root>\Merged` | Where the merged folder goes |
| `-Pattern` | `drive-download-*` | Which folders to merge. Use `takeout-*` for Google Takeout exports |
| `-Move` | | Move files into the destination |
| `-Copy` | | Copy files into the destination |

**Mac and Linux.** It runs in [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell). Use `pwsh ./Merge-DriveChunks.ps1 -Root ~/Downloads/drive`.

### How it decides what's a duplicate

Files are matched by their path inside the chunk folder. When two chunks have a file at the same path, the script compares their size and SHA256 hash. If they match, it's a duplicate and gets skipped. If they don't, both files are kept and the later one is renamed with the chunk number it came from.

After a real run, it checks that every file in the log exists in the destination at the right size. The log is written as the script goes, so a stopped run still has a record.

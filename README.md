# ApacheBAS Projects

A collection of functional applications, utilities, demonstrations, and reference material built for **ApacheBAS**, a server-side BASIC interpreter for Apache on Windows/XAMPP.

The projects in this repository demonstrate that ApacheBAS can be used for much more than simple CGI examples: it can build complete browser applications, system utilities, file explorers, social-network prototypes, repository managers, mathematical visualization tools, image galleries, and local security tools.

## Projects

### ApacheBAS Netstat Monitor
**File:** `netstat.bas`

A read-only network connection monitor built around the Windows `netstat.exe -ano` command. ApacheBAS executes Netstat on the server, returns the raw result through a small API mode, and the browser converts it into an interactive table.

The interface displays TCP and UDP connections, local and remote addresses, connection states, and process IDs. It also provides live filtering, state filtering, manual refresh, connection counters, and automatic refresh every five seconds.

---

### ApacheBAS Programs Explorer
**File:** `programs.bas`

A browser-based program explorer that scans the visible Apache directory tree for Windows executable files. Programs are presented in an Explorer-style list with their relative paths and can be filtered by name or location.

A double-click sends the selected executable path back to ApacheBAS, which starts the program on the server through the `START` statement. The application also reports how many directories were scanned and how many executable programs were found.

---

### ApacheBAS Task Manager
**File:** `task_manager.bas`

A read-only Windows process viewer implemented with ApacheBAS and `tasklist.exe`. It displays the running process name, PID, session, session number, and memory usage in a browser interface.

The process list can be filtered interactively and refreshed manually or automatically. The application is intentionally limited to monitoring and does not terminate or modify processes.

---

### ApacheBAS Server Explorer
**Directory:** `explorer/`

A browser-based file explorer for directories served by Apache. The application provides directory navigation, an address field, a directory tree, file listings, back/up navigation, and an integrated viewer.

Directories can be opened directly, `.bas` applications can be executed inside the viewer, and text, source code, images, PDF documents, HTML pages, audio, and video can be displayed through suitable browser views. Executables placed in an ApacheBAS `tools` directory can also be launched through the server-side `START` mechanism.

---

### ApacheBAS Desktop
**Package:** `desktop/ApacheBAS-Desktop-v1.1.1.zip`

A classic Windows-inspired desktop implemented in the browser and backed by ApacheBAS. It provides desktop icons, a Start menu, taskbar, clock, draggable windows, Explorer-style folder browsing, context menus, and familiar File/Edit/View/Help controls.

The desktop supports multiple selection, copy, move, rename, new folders, permanent deletion, downloads, validated image uploads, and viewers for text, images, PDF, audio, and video. `.bas` applications and HTML pages can be opened inside desktop windows. File operations are confined to the application's desktop root and are handled through the supplied native helper.

---

### ApacheBAS Remote Desktop
**Directory:** `remote-admin/`  
**Latest package:** `ApacheBAS-Remote-Desktop-v1.0.2.zip`

A small read-only remote desktop viewer for Windows. It captures the server desktop and displays the result in a browser, allowing another computer on a trusted network to observe the current screen.

The refresh interval can be adjusted from 0.5 to 10 seconds and is remembered by the browser. The project intentionally provides no mouse input, keyboard input, command execution, process control, or file control. Localhost access is the default, with an optional setup for authenticated LAN access.

---

### FaceBASIC
**Directory:** `facebasic/`  
**Latest package:** `FaceBASIC v1.3.1.zip`

A compact social-network application written with ApacheBAS, HTML, CSS, and a small amount of browser-side JavaScript. It demonstrates how a complete multi-user web application can be implemented without a database or external server-side runtime.

FaceBASIC supports account registration, login and logout, a shared chronological feed, text posts, image posts, combined text-and-image posts, and per-user profile pictures. Uploaded PNG, JPEG, GIF, and WebP images are stored locally, while account and post information is maintained in simple files managed by ApacheBAS.

---

### ApacheBAS Picture Repositories
**Directory:** `gallery/`  
**Current source:** `ApacheBAS-Picture-Repositories-CLEAN-SOURCE-v1.5`

A pair of image-repository applications demonstrating ApacheBAS file storage and binary upload support.

The **Simple Picture Repository** is a public gallery where users can upload, display, and delete PNG, JPEG, GIF, and WebP images with titles. It supports up to 500 active pictures in the demonstration configuration.

The **Account Picture Repository** adds registration and login, giving each user a separate personal gallery. Users can upload and delete their own images, add captions, and maintain an individual collection. The demonstration configuration supports up to 200 active pictures per account.

Both versions use ordinary files for metadata and ApacheBAS `SAVEUPLOAD`, `READFILE$`, `WRITEFILE`, `APPENDFILE`, and `INCLUDE` facilities rather than a database.

---

### GitBASIC
**Directory:** `github/GitBASIC/`  
**Package:** `GitBASIC-ApacheBAS-v1.0.zip`

A small GitHub-inspired source repository service implemented with ApacheBAS. It demonstrates account management, public repositories, source-file storage, README content, descriptions, and image assets without requiring a database.

Users can create accounts, create public repositories, add source or text files, paste file contents, upload image assets, edit repository descriptions and README text, view source files safely as escaped text, open raw text representations, remove files, and remove repositories from the public index. Public repositories can also be browsed without an account.

GitBASIC is intended as a compact demonstration of repository-style web software rather than a replacement for Git or GitHub.

---

### MathBASIC Studio
**Directory:** `mathbasic/`  
**Version:** 1.0.3

A server-side mathematical drawing laboratory in which ApacheBAS performs the mathematical calculations and generates SVG graphics returned to the browser.

Included systems are:

- Mandelbrot set
- Julia set
- Burning Ship fractal
- Sierpinski chaos game
- Lissajous curves
- Polar roses
- hypotrochoid / spirograph curves
- phyllotaxis
- Lorenz attractor
- wave-interference fields

JavaScript is used only for the controls, presets, preview refresh, and SVG download. The mathematical coordinates themselves are calculated by `mathbasic.bas` on the server.

---

### VirusBASIC
**Directory:** `virusbasic/`

A local VirusTotal-style file triage application built with ApacheBAS and a small native hashing helper. Files selected in the browser are sent to the local XAMPP server for static inspection without being executed.

The helper calculates MD5, SHA-1, and SHA-256 hashes, recognizes several common file signatures, reports simple filename and structural indicators, and passes the results to ApacheBAS. ApacheBAS checks the calculated hash against a local signature database and presents the result in the browser. The supplied database includes the standard EICAR antivirus test signature.

The helper processes files in memory, does not intentionally store or execute the uploaded sample, and accepts files up to 32 MiB. A SHA-256 result can also be opened on VirusTotal for an external lookup without automatically uploading the file.

---

### ApacheBAS Language Reference
**Directory:** `html/`

A complete browser-based language reference for ApacheBAS v0.1.34.3, provided in English and Romanian.

The reference documents language basics, flow control, variables, arrays, DATA statements, string functions, mathematical functions, time and random functions, operators, CGI variables, response directives, HTML templates, file operations, source inclusion, uploads, and native-process functions. Entries include syntax descriptions and copyable examples, with built-in search for quickly locating commands and concepts.

## What the collection demonstrates

Taken together, these projects exercise a broad part of the ApacheBAS runtime, including:

- CGI GET and POST processing;
- mixed BASIC/HTML templates;
- file creation, reading, appending, and inclusion;
- binary image uploads;
- execution and startup of native programs;
- integration with Windows command-line utilities;
- user accounts and file-based application state;
- server-generated SVG graphics;
- interactive browser interfaces backed by `.bas` programs;
- local system monitoring and administration tools.

All projects in this collection are functional examples. Some are intentionally designed for **local use or trusted LAN environments** and should be hardened before exposure to the public Internet.

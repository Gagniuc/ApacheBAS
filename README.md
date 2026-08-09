# ApacheBAS

**ApacheBAS** is a compact server-side BASIC interpreter for **Apache HTTP Server** on Windows. The runtime is written entirely in **32-bit x86 assembly language**, assembled with **FASM**, and designed to execute `.bas` files directly through the Common Gateway Interface (CGI). The repository contains both the **ApacheBAS interpreter source code** and a collection of **fully functional ApacheBAS applications and experiments** that demonstrate how the language can be used for web applications, local administration tools, file management, mathematical visualization, image repositories, social-network prototypes, source-code repositories, and security utilities. ApacheBAS is intentionally small and self-contained. The compiled runtime is a Win32 Portable Executable that requires no C runtime, no external language runtime, no linker at build time, and imports operating-system functions only from `KERNEL32.DLL`.

<div align="center">
	<a href="https://github.com/Gagniuc/ApacheBAS/tree/main/bin">
	  <kbd>
	    <img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/ban/gpt%20(III).png" alt="ApacheBAS">
	  </kbd>
	</a>
</div>

---

## Repository structure

```text
ApacheBAS/
└── src/
    ├── ApacheBAS/
    │   └── ApacheBAS.asm
    │
    └── BAS experiments/
        ├── netstat.bas
        ├── programs.bas
        ├── task_manager.bas
        ├── desktop/
        ├── explorer/
        ├── facebasic/
        ├── gallery/
        ├── github/
        ├── html/
        ├── mathbasic/
        ├── remote-admin/
        └── virusbasic/
```

The repository is organized around the ApacheBAS interpreter and a collection of practical examples built with it. The interpreter source is located in `src/ApacheBAS/`, while `src/BAS experiments/` contains complete, functional applications and experiments that demonstrate ApacheBAS in real use rather than as isolated syntax examples.

Alongside the ApacheBAS interpreter source, this repository includes a set of small but functional projects that show the language in use. Some are practical tools, such as file browsing, remote administration, and security-oriented utilities; others are more application-oriented, including a gallery, a social-style interface, a repository-style interface, and mathematical visualization experiments. A selection of these projects is shown below, while additional examples can be revealed with “More ApacheBAS projects [+]”. Together, they give a quick view of the range of applications already built with ApacheBAS, from system-oriented utilities to interactive web interfaces.


<div align="center">
	<a href=""><kbd><img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/task%20manager.png" width="250" alt="ApacheBAS"></kbd></a>
	<a href=""><kbd><img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/explorer.png" width="250" alt="ApacheBAS"></kbd></a>
	<a href=""><kbd><img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/remote.png" width="250" alt="ApacheBAS"></kbd></a>
</div>


<div align="center">
	<a href=""><kbd><img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/gallery.png" width="250" alt="ApacheBAS"></kbd></a>
	<a href=""><kbd><img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/netstat%20(II).png" width="250" alt="ApacheBAS"></kbd></a>
	<a href=""><kbd><img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/programs.png" width="250" alt="ApacheBAS"></kbd></a>
</div>

<br>

<div align="center">
<details>
<summary>More ApacheBAS projects [+]</summary>
	
<div align="center">
	<a href=""><kbd><img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/desktop.png" width="250" alt="ApacheBAS"></kbd></a>
	<a href=""><kbd><img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/facebasic%20(II).png" width="250" alt="ApacheBAS"></kbd></a>
	<a href=""><kbd><img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/gitbasic%20(III).png" width="250" alt="ApacheBAS"></kbd></a>
</div>
	
<div align="center">
	<a href=""><kbd><img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/virusbasic%20(II).png" width="250" alt="ApacheBAS"></kbd></a>
	<a href=""><kbd><img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/virusbasic%20(I).png" width="250" alt="ApacheBAS"></kbd></a>
	<a href=""><kbd><img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/math%20(II).png" width="250" alt="ApacheBAS"></kbd></a>
</div>
	
</details>
</div>

---

# ApacheBAS interpreter

The current ApacheBAS source is a **single FASM source file**. It implements the interpreter, CGI interface, expression evaluator, control-flow engine, file operations, process execution, template system, variable storage, arrays, HTTP response generation, and error handling in one self-contained assembly-language program.

### Current implementation

- ApacheBAS-ASM v0.1.34.3
- 32-bit x86
- Win32 Portable Executable
- FASM 1.x source
- Runs on both 32-bit and 64-bit Windows
- Compatible with Apache/XAMPP through CGI
- No C runtime
- No external `.inc` files
- No separate linker
- Imports only `KERNEL32.DLL`

Because CGI programs are launched as external processes, the 32-bit ApacheBAS executable can be used with a 64-bit Apache/XAMPP installation.

<div align="center">
	<a href="https://github.com/Gagniuc/ApacheBAS/">
	  <kbd>
	    <img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/ban/gpt%20(XIV).png" alt="ApacheBAS">
	  </kbd>
	</a>
</div>

---

## Building ApacheBAS

ApacheBAS can be assembled directly with Flat Assembler:

```text
fasm ApacheBAS.asm ApacheBAS.exe
```

No additional linker or runtime library is required.

---

## Installing under XAMPP/Apache

Copy the executable to the Apache CGI directory:

```text
C:\xampp\cgi-bin\ApacheBAS.exe
```

Then configure Apache to associate `.bas` files with ApacheBAS:

```apache
AddHandler apachebas-script .bas
Action apachebas-script "/cgi-bin/ApacheBAS.exe"
```

Restart Apache after changing the configuration.

A `.bas` file placed under the Apache document root can then be executed directly through the browser.

Example:

```text
http://localhost/hello.bas
```

---

# Language features

ApacheBAS implements a practical subset of BASIC together with extensions intended specifically for server-side programming.

## Core BASIC

Supported language elements include:

- `PRINT`
- `?` as an alias for `PRINT`
- `INPUT` in direct/local execution
- `CLS`
- `CLEAR`
- `CLR`
- `STOP`
- `END`
- `REM`
- apostrophe comments
- numeric variables
- string variables
- assignment
- labels
- classic BASIC line numbers

`INPUT` is intentionally disabled while ApacheBAS is running as a CGI process.

---

## Conditional execution

ApacheBAS supports one-line conditional statements:

```basic
IF condition THEN statement
IF condition THEN statement ELSE statement
```

Example:

```basic
IF name$ = "" THEN name$ = "Citizen"
```

---

## Loops

Supported loop forms include:

```basic
FOR i = 1 TO 10
    PRINT i
NEXT i
```

```basic
WHILE condition
    ...
WEND
```

```basic
DO WHILE condition
    ...
LOOP
```

```basic
DO UNTIL condition
    ...
LOOP
```

```basic
DO
    ...
LOOP WHILE condition
```

```basic
DO
    ...
LOOP UNTIL condition
```

Plain `DO ... LOOP` is also supported.

Loop nesting is supported.

---

## Program flow and subroutines

ApacheBAS provides traditional BASIC program flow:

- `GOTO`
- `GO TO`
- `GOSUB`
- `RETURN`
- named labels
- numeric line numbers

---

## Arrays and DATA

The interpreter supports one-dimensional numeric and string arrays.

Available statements and functions include:

- `OPTION BASE 0`
- `OPTION BASE 1`
- `DIM`
- explicit lower and upper bounds with `TO`
- `AS STRING`
- `LBOUND()`
- `UBOUND()`
- `DATA`
- `READ`
- `RESTORE`
- `SWAP`

Example:

```basic
OPTION BASE 1
DIM values(1 TO 10)

FOR i = 1 TO 10
    values(i) = i * i
NEXT i
```

---

## Numeric expressions

ApacheBAS supports integer and decimal expressions, parentheses, operator precedence, and the following operators:

```text
+  -  *  /  \  MOD  ^
```

Comparison operators:

```text
=  <>  <  <=  >  >=
```

Logical operators:

```text
AND  OR  XOR  NOT
```

String concatenation can be performed with:

```text
+
&
```

Supported integer literal forms include:

```text
&HFF        hexadecimal
&O377       octal
&B101010    binary
```

Constants include:

```text
TRUE
FALSE
PI
```

---

# Built-in functions

## String functions

ApacheBAS includes:

```text
LEN()
LEFT$()
RIGHT$()
MID$()
UCASE$()
LCASE$()
TRIM$()
LTRIM$()
RTRIM$()
HTML$()
JSON$()
STR$()
CHR$()
INSTR()
SPACE$()
STRING$()
```

## Numeric and conversion functions

```text
VAL()
HEX$()
OCT$()
ABS()
SGN()
INT()
FIX()
SQR()
CINT()
CLNG()
CDBL()
CSNG()
SIN()
COS()
TAN()
ATN()
LOG()
EXP()
ASC()
```

## Time and random functions

```text
RANDOMIZE
RND
TIMER
SLEEP
TIME$
DATE$
```

---

# CGI and web programming

ApacheBAS was designed to make CGI data available directly as BASIC variables.

## GET variables

Query-string fields are exposed using the `GET_` prefix.

For:

```text
http://localhost/test.bas?name=Paul
```

the BASIC program can use:

```basic
PRINT GET_NAME$
```

---

## POST variables

`application/x-www-form-urlencoded` POST data are parsed automatically and exposed through `POST_*` variables.

Example:

```basic
PRINT POST_NAME$
```

---

## Cookies

Cookies are available through the `COOKIE_*` variable family.

Example:

```basic
PRINT COOKIE_SESSION$
```

---

## Server variables

Standard CGI and HTTP environment information is made available through `SERVER_*` variables, including request method, query string, content type, content length, remote address, script information, URI, protocol, host, user agent, referrer, accepted content types, and accepted languages.

---

# HTTP response directives

ApacheBAS programs can control the HTTP response using special directives:

```text
@@STATUS
@@CONTENT-TYPE
@@HEADER
```

These allow a `.bas` application to define the HTTP status, content type, and additional response headers.

---

# HTML/BASIC templates

ApacheBAS can execute both pure BASIC files and mixed HTML/BASIC templates.

Executable BASIC blocks use:

```html
<?bas
    ...
?>
```

Expression output uses:

```html
<?= expression ?>
```

Example:

```html
<html>
<body>

<h2>Roma Aeterna</h2>

<?bas
    name$ = get_name$
    sum = 0

    for i = 1 to 10
        sum = sum + i * i
    next i

    if name$ = "" then name$ = "Citizen"
?>

<p>Hello, <?= html$(name$) ?>!</p>
<p>Sum of squares: <?= sum ?></p>

</body>
</html>
```

This permits `.bas` files to combine document markup and BASIC code in a form similar to traditional server-side template systems.

---

# File and application functions

ApacheBAS includes several operations intended for small server-side applications.

## Source inclusion

```basic
INCLUDE
```

Included files execute in the same variable scope and may contain BASIC code, HTML, or mixed templates.

## Text files

```basic
WRITEFILE
APPENDFILE
READFILE$()
```

## Binary files

```basic
READHEX$()
```

## Uploads

```basic
SAVEUPLOAD
```

`SAVEUPLOAD` provides bounded binary image-upload storage in an application-specific upload directory.

---

# External programs

ApacheBAS can use native Windows executables as extensions to the language.

## EXEC

`EXEC` starts an external executable, waits for completion, captures its standard output, and makes the result available to the ApacheBAS program.

This allows external utilities to provide functions that are not implemented directly inside the interpreter.

Examples include:

- cryptographic hashing;
- database helpers;
- image processing;
- operating-system utilities;
- specialized command-line tools.

## START

`START` launches a Windows executable normally without waiting for it to terminate and without capturing its output.

This is useful for local administrative applications and desktop-oriented experiments.

---

# ApacheBAS applications and experiments

The repository contains a collection of complete applications that demonstrate the language in practical use.

All projects listed below are functional. Some are experimental demonstrations intended primarily for localhost or trusted LAN use.

---

## ApacheBAS Netstat Monitor

**File:** `netstat.bas`

A browser-based network connection monitor that obtains connection information from Windows `netstat.exe -ano`.


<div align="center">
	<a href="https://github.com/Gagniuc/ApacheBAS/tree/main/src/BAS%20experiments">
	  <kbd>
	    <img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/netstat%20(I).png" alt="ApacheBAS Netstat Monitor">
	  </kbd>
	</a>
</div>



<div align="center">
	<a href="https://github.com/Gagniuc/ApacheBAS/tree/main/src/BAS%20experiments">
	  <kbd>
	    <img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/netstat%20(II).png" alt="ApacheBAS Netstat Monitor">
	  </kbd>
	</a>
</div>


It displays:

- TCP connections;
- UDP endpoints;
- local addresses;
- remote addresses;
- connection states;
- process IDs;
- connection counts;
- interactive filtering;
- automatic refresh.

The project demonstrates ApacheBAS integration with Windows command-line utilities and the use of a `.bas` program as a small server-side API.

---

## ApacheBAS Programs Explorer

**File:** `programs.bas`

A browser-based explorer for executable programs visible to the ApacheBAS application. The interface scans directories, lists executable files, provides filtering by name or path, and allows an executable to be started through the ApacheBAS `START` statement. It demonstrates filesystem traversal, server-generated interfaces, browser interaction, and native process launching.

<div align="center">
	<a href="https://github.com/Gagniuc/ApacheBAS/tree/main/src/BAS%20experiments">
	  <kbd>
	    <img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/programs.png" alt="ApacheBAS Programs Explorer">
	  </kbd>
	</a>
</div>

---

## ApacheBAS Task Manager

**File:** `task_manager.bas`

A read-only Windows process viewer based on `tasklist.exe`.

<div align="center">
	<a href="https://github.com/Gagniuc/ApacheBAS/tree/main/src/BAS%20experiments">
	  <kbd>
	    <img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/task%20manager.png" alt="ApacheBAS Task Manager">
	  </kbd>
	</a>
</div>

The application presents:

- process name;
- PID;
- session;
- session number;
- memory consumption;
- interactive filtering;
- automatic refresh.

The project is intentionally a monitoring tool and does not terminate or modify running processes.

---

## ApacheBAS Server Explorer

**Directory:** `explorer/`

A browser-based file explorer for directories exposed through Apache.

<div align="center">
	<a href="https://github.com/Gagniuc/ApacheBAS/tree/main/src/BAS%20experiments">
	  <kbd>
	    <img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/explorer.png" alt="ApacheBAS Server Explorer">
	  </kbd>
	</a>
</div>

Features include:

- directory navigation;
- directory tree;
- address field;
- Back and Up navigation;
- file listings;
- integrated file viewer;
- execution of `.bas` applications;
- viewing text and source files;
- image viewing;
- PDF viewing;
- HTML viewing;
- audio and video support;
- launching approved executable tools through `START`.

The project demonstrates how ApacheBAS can act as the server-side engine of a complete file-management interface.

---

## ApacheBAS Desktop

**Directory:** `desktop/`

A Windows-inspired browser desktop backed by ApacheBAS.

<div align="center">
	<a href="https://github.com/Gagniuc/ApacheBAS/tree/main/src/BAS%20experiments">
	  <kbd>
	    <img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/desktop.png" alt="ApacheBAS Desktop">
	  </kbd>
	</a>
</div>

The application includes:

- desktop icons;
- Start menu;
- taskbar;
- clock;
- draggable windows;
- Explorer-style folders;
- context menus;
- file selection;
- copy;
- move;
- rename;
- folder creation;
- deletion;
- downloads;
- image uploads;
- file viewers;
- execution of `.bas` applications;
- HTML applications displayed inside desktop windows.

The project demonstrates a much larger browser interface built on top of ApacheBAS file and process facilities.

---

## ApacheBAS Remote Desktop

**Directory:** `remote-admin/`

A lightweight read-only Windows remote desktop viewer. It captures the current server desktop and displays the image in a browser. The refresh interval is adjustable and can be remembered by the browser. The project intentionally provides no remote mouse or keyboard control. It is primarily intended for localhost or trusted network demonstrations.

<div align="center">
	<a href="https://github.com/Gagniuc/ApacheBAS/tree/main/src/BAS%20experiments">
	  <kbd>
	    <img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/remote.png" alt="ApacheBAS Remote Desktop">
	  </kbd>
	</a>
</div>

---

## FaceBASIC

**Directory:** `facebasic/`

A small social-network application built with ApacheBAS, HTML, CSS, and limited browser-side JavaScript.

<div align="center">
	<a href="https://github.com/Gagniuc/ApacheBAS/tree/main/src/BAS%20experiments">
	  <kbd>
	    <img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/facebasic%20(II).png" alt="FaceBASIC">
	  </kbd>
	</a>
</div>

Features include:

- user registration;
- login and logout;
- user profiles;
- profile pictures;
- chronological feed;
- text posts;
- image posts;
- combined text and image posts.

Account and post data are stored in ordinary files rather than a database. FaceBASIC demonstrates that ApacheBAS can support a complete multi-user web application using only the language runtime and local files.

---

## ApacheBAS Picture Repositories

**Directory:** `gallery/`

A collection of image-gallery applications demonstrating binary uploads and file-based metadata.

<div align="center">
	<a href="https://github.com/Gagniuc/ApacheBAS/tree/main/src/BAS%20experiments">
	  <kbd>
	    <img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/gallery.png" alt="ApacheBAS Picture Repositories">
	  </kbd>
	</a>
</div>

### Simple Picture Repository

A public image gallery supporting:

- PNG;
- JPEG;
- GIF;
- WebP;
- image titles;
- upload;
- display;
- deletion.

### Account Picture Repository

A multi-user version that adds:

- registration;
- login;
- separate user galleries;
- image captions;
- per-user upload and deletion.

These projects use ApacheBAS file functions rather than an external database.

---

## GitBASIC

**Directory:** `github/GitBASIC/`

A compact GitHub-inspired source repository service implemented with ApacheBAS.

<div align="center">
	<a href="https://github.com/Gagniuc/ApacheBAS/tree/main/src/BAS%20experiments">
	  <kbd>
	    <img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/gitbasic%20(III).png" alt="GitBASIC">
	  </kbd>
	</a>
</div>

Features include:

- account creation;
- login;
- public repositories;
- repository descriptions;
- README content;
- source and text files;
- image assets;
- escaped source-code display;
- raw file views;
- file removal;
- repository removal;
- public browsing without an account.

GitBASIC is not intended to reproduce Git itself. It demonstrates how repository-style web software can be implemented using ApacheBAS and ordinary filesystem storage.

---

## MathBASIC Studio

**Directory:** `mathbasic/`

A mathematical graphics laboratory in which ApacheBAS performs calculations on the server and generates SVG graphics for the browser.

<div align="center">
	<a href="https://github.com/Gagniuc/ApacheBAS/tree/main/src/BAS%20experiments">
	  <kbd>
	    <img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/math%20(I).png" alt="MathBASIC Studio">
	  </kbd>
	</a>
</div>


<div align="center">
	<a href="https://github.com/Gagniuc/ApacheBAS/tree/main/src/BAS%20experiments">
	  <kbd>
	    <img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/math%20(II).png" alt="MathBASIC Studio">
	  </kbd>
	</a>
</div>


<div align="center">
	<a href="https://github.com/Gagniuc/ApacheBAS/tree/main/src/BAS%20experiments">
	  <kbd>
	    <img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/math%20(III).png" alt="MathBASIC Studio">
	  </kbd>
	</a>
</div>

<div align="center">
	<a href="https://github.com/Gagniuc/ApacheBAS/tree/main/src/BAS%20experiments">
	  <kbd>
	    <img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/math%20(IV).png" alt="MathBASIC Studio">
	  </kbd>
	</a>
</div>

Included demonstrations include:

- Mandelbrot set;
- Julia set;
- Burning Ship fractal;
- Sierpinski chaos game;
- Lissajous curves;
- polar roses;
- hypotrochoid / spirograph curves;
- phyllotaxis;
- Lorenz attractor;
- wave-interference fields.

The mathematical coordinates are calculated by ApacheBAS. Browser-side JavaScript is used mainly for controls, refresh behavior, presets, and SVG download.

---

## VirusBASIC

**Directory:** `virusbasic/`

A local VirusTotal-style static file-triage application implemented with ApacheBAS and a small native hashing helper.

<div align="center">
	<a href="https://github.com/Gagniuc/ApacheBAS/tree/main/src/BAS%20experiments">
	  <kbd>
	    <img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/virusbasic%20(I).png" alt="VirusBASIC">
	  </kbd>
	</a>
</div>

<div align="center">
	<a href="https://github.com/Gagniuc/ApacheBAS/tree/main/src/BAS%20experiments">
	  <kbd>
	    <img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/virusbasic%20(II).png" alt="VirusBASIC">
	  </kbd>
	</a>
</div>

<div align="center">
	<a href="https://github.com/Gagniuc/ApacheBAS/tree/main/src/BAS%20experiments">
	  <kbd>
	    <img src="https://github.com/Gagniuc/ApacheBAS/blob/main/htm/img/virusbasic%20(III).png" alt="VirusBASIC">
	  </kbd>
	</a>
</div>

The application can:

- calculate MD5;
- calculate SHA-1;
- calculate SHA-256;
- recognize common file signatures;
- inspect simple filename and structural indicators;
- compare calculated hashes against a local signature database;
- identify the standard EICAR antivirus test signature;
- open a SHA-256 lookup on VirusTotal.

Files are inspected rather than executed.

The native helper exists because cryptographic hash functions are not implemented directly by the ApacheBAS language runtime. This also demonstrates how `EXEC` can extend ApacheBAS through a specialized native component.

---

## ApacheBAS Language Reference

**Directory:** `html/`

A browser-based <a href="https://github.com/Gagniuc/ApacheBAS/tree/main/htm">language reference</a> for ApacheBAS v0.1.34.3. English and Romanian versions document:

- BASIC syntax;
- variables;
- arrays;
- flow control;
- DATA statements;
- operators;
- numeric functions;
- string functions;
- time and random functions;
- CGI variables;
- response directives;
- templates;
- file operations;
- uploads;
- source inclusion;
- native process execution.

The reference includes examples and searchable documentation for the implemented language.

---

# What the repository demonstrates

The source code and projects together show ApacheBAS at two different levels. The **interpreter source** demonstrates how a server-side programming language can be implemented directly in x86 assembly with a very small dependency surface. The **application collection** demonstrates how that runtime can be used to construct real browser-facing software. Across the projects, ApacheBAS is used for:

- CGI execution;
- GET and POST parsing;
- cookies;
- server variables;
- HTML/BASIC templates;
- response headers;
- file storage;
- source inclusion;
- binary uploads;
- local application state;
- native executable integration;
- process monitoring;
- network monitoring;
- file management;
- account systems;
- image galleries;
- repository-style applications;
- mathematical visualization;
- static security analysis;
- browser-based administrative interfaces.

---

# Design philosophy

ApacheBAS follows a deliberately simple model:

1. Apache receives a request for a `.bas` file.
2. Apache launches `ApacheBAS.exe` as a CGI process.
3. ApacheBAS reads the CGI environment and request body.
4. The `.bas` source is loaded.
5. BASIC statements and template blocks are interpreted.
6. ApacheBAS constructs the response.
7. The response is returned through standard output.
8. The process terminates.

Each request therefore begins with a fresh interpreter state. The goal is not to reproduce the size or feature set of a mature general-purpose web runtime. ApacheBAS instead explores how much useful server-side functionality can be provided by a compact BASIC interpreter whose implementation remains small, visible, and directly connected to the Apache CGI execution model.

---

# Runtime limits

The current implementation uses explicit resource bounds, including limits for script size, request-body size, response size, variables, arrays, DATA items, loop nesting, GOSUB depth, source inclusion, external-process output, and execution counts. Important current capacities include:

- source buffer: 4 MiB;
- request body: 1 MiB;
- response buffer: 4 MiB;
- scalar variables: 1,024;
- arrays: 32;
- DATA items: 512;
- FOR nesting: 16;
- WHILE nesting: 16;
- DO nesting: 16;
- GOSUB depth: 32;
- INCLUDE depth: 8;
- captured `EXEC` output: 1 MiB.

These limits are intentional parts of the present runtime design.

---

# Intended use

ApacheBAS is suitable for:

- experimentation with programming-language implementation;
- learning BASIC;
- learning CGI;
- teaching server-side programming;
- studying interpreter architecture;
- small local web applications;
- localhost tools;
- trusted-LAN utilities;
- rapid experiments;
- legacy-oriented software research.

Several projects interact with the local operating system, filesystem, processes, or external executables. Those applications should not be exposed directly to an untrusted public network without additional authentication, access control, input validation, and security hardening.

---

# Project status

ApacheBAS and the applications included in this repository are functional. The repository represents both the interpreter itself and a practical collection of programs created to exercise and demonstrate its server-side language facilities.


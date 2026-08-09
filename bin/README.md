# ApacheBAS Executable

`ApacheBAS.exe` is the compiled ApacheBAS runtime. It can be used as a CGI interpreter for `.bas` files under Apache/XAMPP, or launched directly for local BASIC execution.

## Use with XAMPP / Apache

### 1. Copy the executable

Copy:

```text
ApacheBAS.exe
```

to:

```text
C:\xampp\cgi-bin\ApacheBAS.exe
```

### 2. Configure Apache

Open the Apache configuration file (C:\xampp\apache\conf\httpd.conf) and add at the end of the file:

```apache
AddHandler apachebas-script .bas
Action apachebas-script "/cgi-bin/ApacheBAS.exe"
```

### 3. Restart Apache

Open the XAMPP Control Panel and restart Apache.

### 4. Create a BASIC web program

Create:

```text
C:\xampp\htdocs\hello.bas
```

with:

```basic
PRINT "Hello from ApacheBAS!"
```

### 5. Run it in the browser

Open:

```text
http://localhost/hello.bas
```

If ApacheBAS is configured correctly, the browser should display:

```text
Hello from ApacheBAS!
```

---

## Mixed HTML/BASIC pages

ApacheBAS also supports HTML pages containing embedded BASIC code.

Example:

```html
<html>
<body>

<h1>ApacheBAS</h1>

<?bas
name$ = get_name$
if name$ = "" then name$ = "Visitor"
?>

<p>Hello, <?= html$(name$) ?>!</p>

</body>
</html>
```

Save it as:

```text
C:\xampp\htdocs\welcome.bas
```

and open:

```text
http://localhost/welcome.bas?name=Paul
```

---

## Direct local execution

`ApacheBAS.exe` can also run outside Apache.

When no CGI environment is present, ApacheBAS uses direct/local execution and writes BASIC program output directly to the console.

This mode is useful for local tests and BASIC programs that do not require HTTP request data.

---

## Important

ApacheBAS executes `.bas` files as server-side programs. Do not expose file-management, process-execution, upload, or administrative scripts to an untrusted network without appropriate authentication and access controls.

## Build information

The executable is produced from the single-file FASM source with:

```text
fasm ApacheBAS.asm ApacheBAS.exe
```

The current ApacheBAS implementation does not require a C runtime, external include files, or a separate linker and imports operating-system functions only from `KERNEL32.DLL`.

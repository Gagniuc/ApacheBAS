; ============================================================================
; ApacheBAS-ASM v0.1.34.3
; A single-file server-side BASIC CGI runtime for Apache/XAMPP
;
; Build (flat assembler 1):
;     fasm ApacheBAS.asm ApacheBAS.exe
;
; Install:
;     copy ApacheBAS.exe C:\xampp\cgi-bin\ApacheBAS.exe
;     restart Apache
;
; The existing Apache mapping remains valid:
;     AddHandler apachebas-script .bas
;     Action apachebas-script "/cgi-bin/ApacheBAS.exe"
;
; This source is deliberately self-contained:
;   - no .inc files
;   - no C runtime
;   - no linker
;   - imports only KERNEL32.DLL
;
; v0.1.34.3 language subset:
;   PRINT and ? alias, string/numeric variables, assignment, one-line IF ... THEN/ELSE,
;   hexadecimal (&H), octal (&O) and binary (&B) integer literals,
;   FOR ... TO ... [STEP ...] / NEXT with nesting,
;   WHILE ... / WEND with nesting,
;   DO WHILE/UNTIL ... LOOP, DO ... LOOP WHILE/UNTIL and plain DO/LOOP,
;   labels, classic line numbers, GOTO/GO TO, GOSUB and RETURN,
;   OPTION BASE 0/1, DIM with multiple declarations, explicit lower bounds and AS types, one-dimensional numeric/string arrays, LBOUND() and UBOUND(),
;   DATA, READ and RESTORE with scalar and array targets,
;   SWAP for scalar variables and one-dimensional array elements,
;   CLS, CLEAR/CLR, STOP and END,
;   INPUT in direct/local execution, with INPUT intentionally blocked in CGI mode,
;   integer and six-decimal expressions with precedence and parentheses, + - * / \ MOD ^,
;   = <> < <= > >=, AND OR XOR NOT, string concatenation with + or &,
;   TRUE/FALSE, PI, LEN(), LEFT$(), RIGHT$(), MID$(), UCASE$(), LCASE$(),
;   TRIM$(), LTRIM$(), RTRIM$(), HTML$(), JSON$(), STR$(), VAL(), HEX$(), OCT$(),
;   ABS(), SGN(), INT(), FIX(), SQR(), CINT(), CLNG(), CDBL(), CSNG(), SIN(), COS(), TAN(), ATN(), LOG(), EXP(),
;   ASC(), CHR$(), INSTR(), SPACE$(), STRING$(),
;   RANDOMIZE, RND, TIMER, SLEEP, TIME$, DATE$, GET_*, POST_*, COOKIE_* and SERVER_* CGI variables,
;   complete form-urlencoded GET/POST parsing, cookie parsing and exact-length CGI stdin reads,
;   CGI response directives @@STATUS, @@CONTENT-TYPE and @@HEADER,
;   SAVEUPLOAD for bounded binary image uploads into a per-application uploads directory,
;   INCLUDE for runtime code/templates in the same variable scope,
;   WRITEFILE and APPENDFILE for bounded text files below the application data directory,
;   READFILE$() for text and READHEX$() for binary files,
;   EXEC for relative or PATH-resolved native executables with captured output,
;   START for launching a relative or PATH-resolved Windows executable normally without waiting or capture,
;   pure BASIC files and mixed <?bas ... ?> / <?= ... ?> templates.
;
; Target: Win32 PE console CGI. It runs on both 32-bit and 64-bit Windows,
; including 64-bit XAMPP/Apache, because CGI programs are external processes.
; ============================================================================

format PE console 4.0
entry start

; ----------------------------------------------------------------------------
; Constants
; ----------------------------------------------------------------------------

STD_INPUT_HANDLE        = -10
STD_OUTPUT_HANDLE       = -11
INVALID_HANDLE_VALUE    = -1
GENERIC_READ            = 80000000h
GENERIC_WRITE           = 40000000h
FILE_SHARE_READ         = 1
CREATE_ALWAYS           = 2
OPEN_EXISTING           = 3
OPEN_ALWAYS             = 4
FILE_ATTRIBUTE_NORMAL   = 80h
FILE_BEGIN              = 0
FILE_END                = 2
CREATE_NO_WINDOW        = 08000000h
STARTF_USESHOWWINDOW    = 00000001h
SW_SHOWNORMAL           = 1
STARTF_USESTDHANDLES    = 00000100h
WAIT_OBJECT_0           = 0
WAIT_TIMEOUT            = 00000102h
MEM_COMMIT              = 1000h
MEM_RESERVE             = 2000h
PAGE_READWRITE          = 4

FPU_OP_SIN              = 1
FPU_OP_COS              = 2
FPU_OP_TAN              = 3
FPU_OP_ATN              = 4
FPU_OP_LOG              = 5
FPU_OP_EXP              = 6

MAX_SCRIPT              = 4*1024*1024
MAX_BODY                = 1024*1024
MAX_OUTPUT              = 4*1024*1024
MAX_VARIABLES           = 1024
VAR_NAME_SIZE           = 64
VAR_VALUE_SIZE          = 2048
EXEC_OUTPUT_SIZE        = 1024*1024
EVAL_SIZE               = EXEC_OUTPUT_SIZE
ENV_SIZE                = 8192
PATH_SIZE               = 4096

; Recursive expression evaluator (32-bit signed integer arithmetic).
EVAL_WORK_SLOTS         = 32
EVAL_WORK_SIZE          = 4096
MAX_FOR_DEPTH           = 16
MAX_FOR_ITERATIONS      = 1000000
MAX_WHILE_DEPTH         = 16
MAX_WHILE_ITERATIONS    = 1000000
MAX_DO_DEPTH            = 16
MAX_DO_ITERATIONS       = 1000000
MAX_GOTO_JUMPS          = 1000000
MAX_GOSUB_DEPTH          = 32
MAX_GOSUB_CALLS          = 1000000
MAX_ARRAYS               = 32
MAX_ARRAY_INDEX          = 4095
MAX_DATA_ITEMS           = 512
DATA_ITEM_SIZE           = 256
CONTENT_TYPE_SIZE        = 256
DIRECTIVE_SIZE           = 2048
MAX_CUSTOM_HEADERS       = 8192
MAX_UPLOAD_FILENAME      = 128
MAX_INCLUDE_DEPTH        = 8
MAX_INCLUDE_SIZE         = 512*1024
MAX_FILE_TEXT            = VAR_VALUE_SIZE-1
MAX_FILE_BINARY          = (VAR_VALUE_SIZE-1)/2
MAX_EXEC_COMMAND         = 2048
EXEC_TIMEOUT_MS          = 5000

OP_OR                   = 1
OP_XOR                  = 2
OP_AND                  = 3
OP_EQ                   = 4
OP_NE                   = 5
OP_LT                   = 6
OP_LE                   = 7
OP_GT                   = 8
OP_GE                   = 9
OP_CONCAT               = 10
OP_ADD                  = 11
OP_SUB                  = 12
OP_MUL                  = 13
OP_DIV                  = 14
OP_IDIV                 = 15
OP_MOD                  = 16
OP_POW                  = 17

; ----------------------------------------------------------------------------
; Code
; ----------------------------------------------------------------------------

section '.text' code readable executable

start:
        cld

        ; Allocate large runtime buffers.
        push PAGE_READWRITE
        push MEM_COMMIT or MEM_RESERVE
        push MAX_SCRIPT+1
        push 0
        call [VirtualAlloc]
        mov [script_buffer],eax
        test eax,eax
        jz fatal_allocation

        push PAGE_READWRITE
        push MEM_COMMIT or MEM_RESERVE
        push MAX_BODY+1
        push 0
        call [VirtualAlloc]
        mov [body_buffer],eax
        test eax,eax
        jz fatal_allocation

        push PAGE_READWRITE
        push MEM_COMMIT or MEM_RESERVE
        push MAX_OUTPUT+1
        push 0
        call [VirtualAlloc]
        mov [output_buffer],eax
        test eax,eax
        jz fatal_allocation

        mov [output_length],0
        mov [runtime_error],0
        mov [variable_count],0
        mov [for_depth],0
        mov [while_depth],0
        mov [do_depth],0
        mov [flow_pending],0
        mov [goto_jump_count],0
        mov [gosub_depth],0
        mov [gosub_call_count],0
        mov [return_pending],0
        mov [program_stop],0
        mov [array_count],0
        mov [option_base],0
        mov [array_last_is_string],0
        mov [data_item_count],0
        mov [data_read_index],0
        mov [data_initialized],0
        mov [current_statement_ptr],0
        mov [current_statement_len],0
        mov [cgi_mode],0
        mov [input_skip_lf],0
        mov dword [request_body_advertised_length],0
        mov dword [upload_handle],INVALID_HANDLE_VALUE
        mov dword [file_handle],INVALID_HANDLE_VALUE
        mov dword [include_handle],INVALID_HANDLE_VALUE
        mov dword [include_depth],0
        mov dword [exec_output_handle],INVALID_HANDLE_VALUE
        mov dword [exec_read_handle],INVALID_HANDLE_VALUE
        mov dword [exec_timed_out],0
        mov dword [exec_output_length],0
        mov dword [exec_output_truncated],0
        mov byte [exec_output_buffer],0
        mov dword [exec_startup_info],68
        mov dword [exec_security_attributes],12
        mov dword [exec_security_attributes+4],0
        mov dword [exec_security_attributes+8],1

        ; Default successful CGI response. PRINT meta-directives may override
        ; these values before the final response is emitted.
        mov dword [response_status_code],200
        mov dword [response_status_line_length],0
        mov dword [response_custom_headers_length],0
        mov esi,default_content_type
        mov edi,response_content_type
        mov ecx,default_content_type_len+1
        rep movsb
        mov byte [response_custom_headers],0

        ; Seed the v0.1.23 linear-congruential PRNG from local time.
        push system_time
        call [GetLocalTime]
        movzx eax,word [system_time+14]    ; milliseconds
        movzx edx,word [system_time+12]    ; seconds
        shl edx,16
        xor eax,edx
        movzx edx,word [system_time+10]    ; minutes
        shl edx,8
        xor eax,edx
        or eax,1
        mov [rnd_seed],eax

        call load_cgi_environment
        call read_request_body
        call parse_request_variables
        call load_script_file
        cmp [runtime_error],0
        jne finish_request

        call execute_loaded_script

finish_request:
        cmp dword [cgi_mode],0
        je .direct_response
        call write_http_response
        jmp .exit
.direct_response:
        call write_direct_response
.exit:
        push 0
        call [ExitProcess]

fatal_allocation:
        push msg_fatal_alloc_len
        push msg_fatal_alloc
        call raw_stdout_write
        push 1
        call [ExitProcess]

; ----------------------------------------------------------------------------
; CGI environment
; ----------------------------------------------------------------------------

load_cgi_environment:
        ; REQUEST_METHOD is set by Apache for CGI requests.  When it is absent,
        ; the runtime is being invoked directly and INPUT may read from stdin.
        mov dword [cgi_mode],0
        push ENV_SIZE
        push env_buffer
        push env_request_method
        call [GetEnvironmentVariableA]
        test eax,eax
        jz .mode_ready
        mov dword [cgi_mode],1
.mode_ready:

        ; Resolve script path.
        push PATH_SIZE
        push script_path
        push env_path_translated
        call [GetEnvironmentVariableA]
        test eax,eax
        jnz .have_path

        push PATH_SIZE
        push script_path
        push env_script_filename
        call [GetEnvironmentVariableA]
.have_path:

        ; Load standard CGI variables into the BASIC symbol table.
        push var_server_method
        push env_request_method
        call env_to_basic_variable

        push var_request_method
        push env_request_method
        call env_to_basic_variable

        push var_server_query
        push env_query_string
        call env_to_basic_variable

        push var_query_string
        push env_query_string
        call env_to_basic_variable

        push var_server_content_type
        push env_content_type
        call env_to_basic_variable

        push var_content_type
        push env_content_type
        call env_to_basic_variable

        push var_server_content_length
        push env_content_length
        call env_to_basic_variable

        push var_content_length
        push env_content_length
        call env_to_basic_variable

        push var_server_cookie
        push env_http_cookie
        call env_to_basic_variable

        push var_server_remote_addr
        push env_remote_addr
        call env_to_basic_variable

        push var_server_script_name
        push env_script_name
        call env_to_basic_variable

        push var_server_script_filename
        push env_path_translated
        call env_to_basic_variable

        push var_server_request_uri
        push env_request_uri
        call env_to_basic_variable

        push var_server_protocol
        push env_server_protocol
        call env_to_basic_variable

        push var_server_name
        push env_server_name
        call env_to_basic_variable

        push var_server_port
        push env_server_port
        call env_to_basic_variable

        push var_server_http_host
        push env_http_host
        call env_to_basic_variable

        push var_server_user_agent
        push env_http_user_agent
        call env_to_basic_variable

        push var_server_referer
        push env_http_referer
        call env_to_basic_variable

        push var_server_accept
        push env_http_accept
        call env_to_basic_variable

        push var_server_accept_language
        push env_http_accept_language
        call env_to_basic_variable

        ret

; stdcall-like internal helper:
;   [esp+4] environment name, [esp+8] BASIC variable name
env_to_basic_variable:
        push ebp
        mov ebp,esp
        push ENV_SIZE
        push env_buffer
        push dword [ebp+8]
        call [GetEnvironmentVariableA]
        cmp eax,ENV_SIZE
        jb .length_ok
        mov eax,ENV_SIZE-1
.length_ok:
        mov byte [env_buffer+eax],0
        push env_buffer
        push dword [ebp+12]
        call set_variable_z
        mov esp,ebp
        pop ebp
        ret 8

read_request_body:
        ; CONTENT_LENGTH -> request_body_length. CGI stdin is a pipe, so a
        ; successful ReadFile is allowed to return fewer bytes than requested.
        ; Keep reading until the advertised body length is satisfied or EOF is
        ; reached. This matters for larger POST requests and busy Apache pipes.
        push ENV_SIZE
        push env_buffer
        push env_content_length
        call [GetEnvironmentVariableA]
        test eax,eax
        jz .none

        mov esi,env_buffer
        call atoi_unsigned
        mov [request_body_advertised_length],eax
        cmp eax,MAX_BODY
        jbe .size_ok
        mov eax,MAX_BODY
.size_ok:
        mov [request_body_length],eax
        test eax,eax
        jz .none

        push STD_INPUT_HANDLE
        call [GetStdHandle]
        mov [stdin_handle],eax
        cmp eax,INVALID_HANDLE_VALUE
        je .none

        xor edi,edi                         ; total bytes read
.read_more:
        mov eax,[request_body_length]
        sub eax,edi                         ; bytes still expected
        jz .read_done

        push 0
        push bytes_done
        push eax
        mov edx,[body_buffer]
        add edx,edi
        push edx
        push dword [stdin_handle]
        call [ReadFile]
        test eax,eax
        jz .read_done

        mov eax,[bytes_done]
        test eax,eax
        jz .read_done
        add edi,eax
        jmp .read_more

.read_done:
        mov [request_body_length],edi
        mov eax,[body_buffer]
        mov byte [eax+edi],0

        push dword [body_buffer]
        push var_server_body
        call set_variable_z
.none:
        ret

parse_request_variables:
        ; GET variables
        push ENV_SIZE
        push env_buffer
        push env_query_string
        call [GetEnvironmentVariableA]
        test eax,eax
        jz .post
        mov byte [env_buffer+eax],0
        push prefix_get
        push env_buffer
        call parse_urlencoded

.post:
        ; POST variables are parsed only for application/x-www-form-urlencoded.
        cmp [request_body_length],0
        je .cookies

        push ENV_SIZE
        push env_buffer
        push env_content_type
        call [GetEnvironmentVariableA]
        mov byte [env_buffer+eax],0
        mov esi,env_buffer
        mov edi,mime_form_urlencoded
        call starts_with_i
        test eax,eax
        jz .cookies

        push prefix_post
        push dword [body_buffer]
        call parse_urlencoded

.cookies:
        push ENV_SIZE
        push env_buffer
        push env_http_cookie
        call [GetEnvironmentVariableA]
        test eax,eax
        jz .done
        mov byte [env_buffer+eax],0
        push prefix_cookie
        push env_buffer
        call parse_cookie_header
.done:
        ret

; parse_urlencoded(text, prefix)
parse_urlencoded:
        push ebp
        mov ebp,esp
        pushad
        mov esi,[ebp+8]
        mov eax,[ebp+12]
        mov [parse_prefix],eax

.next_pair:
        cmp byte [esi],0
        je .done

        mov edi,url_key
        mov ecx,VAR_NAME_SIZE-8
.key_loop:
        mov al,[esi]
        test al,al
        jz .key_done
        cmp al,'='
        je .key_done_eq
        cmp al,'&'
        je .key_done_pair
        call decode_url_char
        call safe_variable_char
        stosb
        dec ecx
        jz .skip_key_tail
        jmp .key_loop

.skip_key_tail:
        mov al,[esi]
        test al,al
        jz .key_done
        cmp al,'='
        je .key_done_eq
        cmp al,'&'
        je .key_done_pair
        inc esi
        jmp .skip_key_tail

.key_done_eq:
        inc esi
.key_done:
        mov al,0
        stosb

        mov edi,url_value
        mov ecx,VAR_VALUE_SIZE-1
.value_loop:
        mov al,[esi]
        test al,al
        jz .value_done
        cmp al,'&'
        je .value_pair_end
        call decode_url_char
        stosb
        dec ecx
        jz .skip_value_tail
        jmp .value_loop

.skip_value_tail:
        mov al,[esi]
        test al,al
        jz .value_done
        cmp al,'&'
        je .value_pair_end
        inc esi
        jmp .skip_value_tail

.value_pair_end:
        inc esi
.value_done:
        mov al,0
        stosb

        cmp byte [url_key],0
        je .next_pair

        ; Build PREFIX + KEY + '$'.
        mov edi,var_build_name
        mov ebx,[parse_prefix]
.copy_prefix:
        mov al,[ebx]
        test al,al
        jz .copy_key
        stosb
        inc ebx
        jmp .copy_prefix
.copy_key:
        mov ebx,url_key
.copy_key_loop:
        mov al,[ebx]
        test al,al
        jz .suffix
        stosb
        inc ebx
        jmp .copy_key_loop
.suffix:
        mov al,'$'
        stosb
        xor al,al
        stosb

        push url_value
        push var_build_name
        call set_variable_z
        jmp .next_pair

.key_done_pair:
        inc esi
        mov al,0
        stosb
        mov byte [url_value],0
        cmp byte [url_key],0
        je .next_pair
        mov edi,var_build_name
        mov ebx,[parse_prefix]
        call copy_z_advance
        mov ebx,url_key
        call copy_z_advance_nozero
        mov byte [edi],'$'
        mov byte [edi+1],0
        push url_value
        push var_build_name
        call set_variable_z
        jmp .next_pair

.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; On entry ESI points at encoded input character.
; Returns decoded byte in AL and advances ESI.
decode_url_char:
        mov al,[esi]
        cmp al,'+'
        jne .percent
        mov al,' '
        inc esi
        ret
.percent:
        cmp al,'%'
        jne .plain
        mov ah,[esi+1]
        test ah,ah
        jz .plain
        mov dl,[esi+2]
        test dl,dl
        jz .plain
        mov al,ah
        call hex_nibble
        cmp al,0FFh
        je .plain_percent
        shl al,4
        mov ah,al
        mov al,dl
        call hex_nibble
        cmp al,0FFh
        je .plain_percent
        or al,ah
        add esi,3
        ret
.plain_percent:
        mov al,'%'
        inc esi
        ret
.plain:
        inc esi
        ret

hex_nibble:
        cmp al,'0'
        jb .bad
        cmp al,'9'
        jbe .digit
        and al,0DFh
        cmp al,'A'
        jb .bad
        cmp al,'F'
        ja .bad
        sub al,'A'-10
        ret
.digit:
        sub al,'0'
        ret
.bad:
        mov al,0FFh
        ret

safe_variable_char:
        cmp al,'a'
        jb .upper_check
        cmp al,'z'
        ja .upper_check
        sub al,20h
        ret
.upper_check:
        cmp al,'A'
        jb .digit_check
        cmp al,'Z'
        jbe .ok
.digit_check:
        cmp al,'0'
        jb .underscore
        cmp al,'9'
        jbe .ok
        cmp al,'_'
        je .ok
.underscore:
        mov al,'_'
.ok:
        ret

; parse_cookie_header(text, prefix)
parse_cookie_header:
        push ebp
        mov ebp,esp
        pushad
        mov esi,[ebp+8]
        mov eax,[ebp+12]
        mov [parse_prefix],eax

.cookie_next:
        call skip_spaces_esi
        cmp byte [esi],0
        je .done
        mov edi,url_key
        mov ecx,VAR_NAME_SIZE-8
.cookie_key:
        mov al,[esi]
        test al,al
        jz .cookie_key_done
        cmp al,'='
        je .cookie_eq
        cmp al,';'
        je .cookie_pair_done
        call safe_variable_char
        stosb
        inc esi
        dec ecx
        jnz .cookie_key
.cookie_eq:
        cmp byte [esi],'='
        jne .cookie_key_done
        inc esi
.cookie_key_done:
        mov byte [edi],0
        mov edi,url_value
        mov ecx,VAR_VALUE_SIZE-1
.cookie_value:
        mov al,[esi]
        test al,al
        jz .cookie_value_done
        cmp al,';'
        je .cookie_semicolon
        stosb
        inc esi
        dec ecx
        jnz .cookie_value
.cookie_semicolon:
        cmp byte [esi],';'
        jne .cookie_value_done
        inc esi
.cookie_value_done:
        mov byte [edi],0

        cmp byte [url_key],0
        je .cookie_next
        mov edi,var_build_name
        mov ebx,[parse_prefix]
        call copy_z_advance
        mov ebx,url_key
        call copy_z_advance_nozero
        mov byte [edi],'$'
        mov byte [edi+1],0
        push url_value
        push var_build_name
        call set_variable_z
        jmp .cookie_next

.cookie_pair_done:
        inc esi
        mov byte [edi],0
        mov byte [url_value],0
        jmp .cookie_next
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; ----------------------------------------------------------------------------
; Script loading
; ----------------------------------------------------------------------------

load_script_file:
        cmp byte [script_path],0
        jne .path_ok
        push msg_no_script
        call set_runtime_error_z
        ret
.path_ok:
        mov esi,script_path
        call has_bas_extension
        test eax,eax
        jnz .extension_ok
        push msg_bad_extension
        call set_runtime_error_z
        ret
.extension_ok:

        push 0
        push FILE_ATTRIBUTE_NORMAL
        push OPEN_EXISTING
        push 0
        push FILE_SHARE_READ
        push GENERIC_READ
        push script_path
        call [CreateFileA]
        cmp eax,INVALID_HANDLE_VALUE
        jne .opened
        push msg_script_open
        call set_runtime_error_z
        ret
.opened:
        mov [script_handle],eax

        push file_size64
        push eax
        call [GetFileSizeEx]
        test eax,eax
        jnz .size_read
        push msg_script_size
        call set_runtime_error_z
        jmp .close
.size_read:
        cmp dword [file_size64+4],0
        jne .too_large
        mov eax,dword [file_size64]
        cmp eax,MAX_SCRIPT
        ja .too_large
        mov [script_length],eax

        push 0
        push bytes_done
        push eax
        push dword [script_buffer]
        push dword [script_handle]
        call [ReadFile]
        test eax,eax
        jnz .read_ok
        push msg_script_read
        call set_runtime_error_z
        jmp .close
.read_ok:
        mov eax,[bytes_done]
        mov [script_length],eax
        mov edi,[script_buffer]
        mov byte [edi+eax],0
        jmp .close
.too_large:
        push msg_script_large
        call set_runtime_error_z
.close:
        push dword [script_handle]
        call [CloseHandle]
        ret

has_bas_extension:
        ; ESI = zero-terminated path. Returns EAX=1 when extension is .bas.
        push esi
        call strlen_esi
        cmp eax,4
        jb .no
        add esi,eax
        sub esi,4
        mov al,[esi]
        cmp al,'.'
        jne .no
        mov al,[esi+1]
        or al,20h
        cmp al,'b'
        jne .no
        mov al,[esi+2]
        or al,20h
        cmp al,'a'
        jne .no
        mov al,[esi+3]
        or al,20h
        cmp al,'s'
        jne .no
        mov eax,1
        pop esi
        ret
.no:
        xor eax,eax
        pop esi
        ret

; ----------------------------------------------------------------------------
; Template and BASIC execution
; ----------------------------------------------------------------------------

execute_loaded_script:
        push dword [script_length]
        push dword [script_buffer]
        call execute_source_span
        ret

; execute_source_span(pointer,length)
; Runs a pure BASIC source or a mixed HTML/BASIC template. Runtime INCLUDE uses
; this entry point, so template and active-program globals are saved/restored.
execute_source_span:
        push ebp
        mov ebp,esp
        pushad
        push dword [template_cursor]
        push dword [template_end]
        push dword [tag_pointer]
        push dword [tag_close_pointer]
        push dword [tag_type]
        push dword [tag_open_length]
        push dword [active_program_start]
        push dword [active_program_end]

        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        mov edi,esi
        add edi,ecx
        push edi
        push esi
        call contains_template_tag
        test eax,eax
        jnz .template

        ; PHP-like convenience for a pure HTML include/template: when a source
        ; has no <?bas/<?= tags and its first non-space character is '<', emit
        ; it literally. Ordinary BASIC sources continue on the proven path.
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        test ecx,ecx
        jz .finish
        cmp byte [esi],'<'
        je .literal_source

        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        mov [active_program_start],esi
        mov eax,esi
        add eax,ecx
        mov [active_program_end],eax
        call prepare_data_table
        cmp dword [runtime_error],0
        jne .finish
        push ecx
        push esi
        call execute_code_block
        jmp .finish

.template:
        mov esi,[ebp+8]
        mov edi,esi
        add edi,[ebp+12]
        mov [template_cursor],esi
        mov [template_end],edi
.next_tag:
        mov esi,[template_cursor]
        mov edi,[template_end]
        cmp esi,edi
        jae .finish
        call find_next_template_tag
        test eax,eax
        jz .literal_tail

        mov [tag_pointer],eax
        mov [tag_type],edx
        mov [tag_open_length],ecx
        mov edx,eax
        sub edx,[template_cursor]
        push edx
        push dword [template_cursor]
        call output_append_span

        mov esi,[tag_pointer]
        add esi,[tag_open_length]
        mov edi,[template_end]
        ; find_template_close advances ESI while scanning. Preserve the content
        ; start so the expression/code span length is not reduced to zero.
        push esi
        call find_template_close
        pop esi
        test eax,eax
        jz .unclosed
        mov [tag_close_pointer],eax
        mov ecx,eax
        sub ecx,esi
        cmp [tag_type],2
        je .expression_tag

        mov [active_program_start],esi
        mov eax,esi
        add eax,ecx
        mov [active_program_end],eax
        call prepare_data_table
        cmp dword [runtime_error],0
        jne .advance
        push ecx
        push esi
        call execute_code_block
        jmp .advance
.expression_tag:
        mov dword [eval_work_depth],0
        push eval_buffer
        push ecx
        push esi
        call evaluate_atom
        push eax
        push eval_buffer
        call output_append_span
.advance:
        mov eax,[tag_close_pointer]
        add eax,2
        mov [template_cursor],eax
        cmp dword [runtime_error],0
        jne .finish
        cmp dword [program_stop],0
        je .next_tag
        jmp .finish
.literal_source:
        push dword [ebp+12]
        push dword [ebp+8]
        call output_append_span
        jmp .finish

.literal_tail:
        mov eax,[template_end]
        sub eax,[template_cursor]
        push eax
        push dword [template_cursor]
        call output_append_span
        jmp .finish
.unclosed:
        push msg_unclosed_template
        call set_runtime_error_z
.finish:
        pop dword [active_program_end]
        pop dword [active_program_start]
        pop dword [tag_open_length]
        pop dword [tag_type]
        pop dword [tag_close_pointer]
        pop dword [tag_pointer]
        pop dword [template_end]
        pop dword [template_cursor]
        popad
        mov esp,ebp
        pop ebp
        ret 8

contains_template_tag:
        push ebp
        mov ebp,esp
        push esi
        push edi
        push ecx
        push edx
        mov esi,[ebp+8]
        mov edi,[ebp+12]
        call find_next_template_tag
        test eax,eax
        setnz al
        movzx eax,al
        pop edx
        pop ecx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 8

; ESI=current, EDI=end. Returns EAX=tag pointer or zero,
; EDX=1 for <?bas, EDX=2 for <?=, ECX=opening length.
find_next_template_tag:
.scan:
        cmp esi,edi
        jae .none
        cmp byte [esi],'<'
        jne .advance
        lea eax,[esi+1]
        cmp eax,edi
        jae .none
        cmp byte [esi+1],'?'
        jne .advance
        lea eax,[esi+2]
        cmp eax,edi
        jae .none
        cmp byte [esi+2],'='
        je .expr

        ; case-insensitive "bas"
        lea eax,[esi+5]
        cmp eax,edi
        ja .advance
        mov al,[esi+2]
        or al,20h
        cmp al,'b'
        jne .advance
        mov al,[esi+3]
        or al,20h
        cmp al,'a'
        jne .advance
        mov al,[esi+4]
        or al,20h
        cmp al,'s'
        jne .advance
        mov eax,esi
        mov edx,1
        mov ecx,5
        ret
.expr:
        mov eax,esi
        mov edx,2
        mov ecx,3
        ret
.advance:
        inc esi
        jmp .scan
.none:
        xor eax,eax
        ret

; ESI=start after opening tag, EDI=end. Returns EAX=pointer to '?' of '?>'.
find_template_close:
.loop:
        cmp esi,edi
        jae .none
        cmp byte [esi],'?'
        jne .advance
        lea eax,[esi+1]
        cmp eax,edi
        jae .none
        cmp byte [esi+1],'>'
        je .found
.advance:
        inc esi
        jmp .loop
.found:
        mov eax,esi
        ret
.none:
        xor eax,eax
        ret

; execute_code_block(pointer,length)
execute_code_block:
        push ebp
        mov ebp,esp
        push esi
        push edi
        push ebx
        mov esi,[ebp+8]
        mov edi,esi
        add edi,[ebp+12]
.line_loop:
        cmp esi,edi
        jae .done
        mov ebx,esi
.find_eol:
        cmp esi,edi
        jae .line_ready
        mov al,[esi]
        cmp al,13
        je .line_ready
        cmp al,10
        je .line_ready
        inc esi
        jmp .find_eol
.line_ready:
        mov ecx,esi
        sub ecx,ebx

        ; FOR/NEXT is handled at block level because it controls a range of
        ; source lines.  Save the line scanner registers because the parser is
        ; intentionally register-based.  EDX returns the first byte after the
        ; matching NEXT when EAX is nonzero.
        push ecx
        push ebx
        push esi
        push edi
        push edi                         ; block end
        push esi                         ; end of FOR line
        push ecx                         ; line length
        push ebx                         ; line pointer
        call execute_for_if_present
        pop edi
        pop esi
        pop ebx
        pop ecx
        test eax,eax
        jnz .block_was_handled

        ; WHILE/WEND is the second block-level construct.  It uses the same
        ; recursive block executor, so WHILE may contain FOR and vice versa.
        push ecx
        push ebx
        push esi
        push edi
        push edi                         ; block end
        push esi                         ; end of WHILE line
        push ecx                         ; line length
        push ebx                         ; line pointer
        call execute_while_if_present
        pop edi
        pop esi
        pop ebx
        pop ecx
        test eax,eax
        jnz .block_was_handled

        ; DO/LOOP is handled independently from WHILE/WEND.  Both pre-test
        ; and post-test forms are supported, and recursive block execution
        ; permits nesting with FOR and WHILE.
        push ecx
        push ebx
        push esi
        push edi
        push edi                         ; block end
        push esi                         ; end of DO line
        push ecx                         ; line length
        push ebx                         ; line pointer
        call execute_do_if_present
        pop edi
        pop esi
        pop ebx
        pop ecx
        test eax,eax
        jz .ordinary_statement

.block_was_handled:
        cmp [runtime_error],0
        jne .done
        cmp dword [program_stop],0
        jne .done
        cmp dword [return_pending],0
        jne .done
        cmp dword [flow_pending],0
        jne .apply_flow
        mov esi,edx
        jmp .line_loop

.ordinary_statement:
        push ecx
        push ebx
        call execute_statement
        cmp [runtime_error],0
        jne .done
        cmp dword [program_stop],0
        jne .done
        cmp dword [return_pending],0
        jne .done
        cmp dword [flow_pending],0
        jne .apply_flow
.skip_eol:
        cmp esi,edi
        jae .line_loop
        mov al,[esi]
        cmp al,13
        je .inc_eol
        cmp al,10
        jne .line_loop
.inc_eol:
        inc esi
        jmp .skip_eol

.apply_flow:
        ; A jump is consumed by the innermost active block that contains its
        ; target.  Otherwise it propagates to the caller, allowing GOTO to
        ; leave FOR/WHILE/DO bodies without corrupting their local stacks.
        mov eax,[flow_target]
        cmp eax,[ebp+8]
        jb .done
        cmp eax,edi
        ja .done
        mov dword [flow_pending],0
        mov esi,eax
        cmp esi,edi
        jae .done
        jmp .line_loop
.done:
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 8

; execute_do_if_present(line_ptr,line_len,line_end,block_end)
; Returns EAX=1 when the line was DO and EDX points after matching LOOP.
; Supported forms:
;     DO WHILE condition ... LOOP
;     DO UNTIL condition ... LOOP
;     DO ... LOOP WHILE condition
;     DO ... LOOP UNTIL condition
; Opening and closing conditions may not be combined on the same loop.
execute_do_if_present:
        push ebp
        mov ebp,esp
        sub esp,52

        mov dword [ebp-4],0              ; opening condition pointer
        mov dword [ebp-8],0              ; opening condition length
        mov dword [ebp-12],0             ; opening mode: 1=WHILE, 2=UNTIL
        mov dword [ebp-16],0             ; body pointer
        mov dword [ebp-20],0             ; body length
        mov dword [ebp-24],0             ; after LOOP
        mov dword [ebp-28],0             ; closing condition pointer
        mov dword [ebp-32],0             ; closing condition length
        mov dword [ebp-36],0             ; closing mode: 1=WHILE, 2=UNTIL
        mov dword [ebp-40],0             ; iteration count
        mov dword [ebp-44],0             ; depth was incremented
        mov dword [ebp-48],0             ; LOOP line pointer
        mov dword [ebp-52],0             ; LOOP line end

        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        push keyword_do
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .is_do
        xor eax,eax
        mov esp,ebp
        pop ebp
        ret 16

.is_do:
        mov edx,[do_depth]
        cmp edx,MAX_DO_DEPTH
        jb .depth_ok
        push msg_do_depth
        call set_runtime_error_z
        jmp .handled
.depth_ok:
        add esi,eax
        sub ecx,eax
        call trim_span
        test ecx,ecx
        jz .opening_done

        push keyword_while
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jz .check_open_until
        mov dword [ebp-12],1
        jmp .store_open_condition
.check_open_until:
        push keyword_until
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jz .bad_do
        mov dword [ebp-12],2
.store_open_condition:
        add esi,eax
        sub ecx,eax
        call trim_span
        test ecx,ecx
        jz .bad_do
        mov [ebp-4],esi
        mov [ebp-8],ecx

.opening_done:
        ; Body begins immediately after the DO line terminator(s).
        mov eax,[ebp+16]
        mov edx,[ebp+20]
.skip_do_eol:
        cmp eax,edx
        jae .body_ready
        mov cl,[eax]
        cmp cl,13
        je .advance_do_eol
        cmp cl,10
        jne .body_ready
.advance_do_eol:
        inc eax
        jmp .skip_do_eol
.body_ready:
        mov [ebp-16],eax

        push dword [ebp+20]
        push eax
        call find_matching_loop
        test eax,eax
        jnz .matching_loop
        push msg_missing_loop
        call set_runtime_error_z
        jmp .handled
.matching_loop:
        mov [ebp-48],eax
        mov [ebp-24],edx
        mov ecx,eax
        sub ecx,[ebp-16]
        mov [ebp-20],ecx

        ; Find the raw end of the matching LOOP line so its optional
        ; WHILE/UNTIL condition can be parsed without CR/LF bytes.
        mov esi,eax
        mov edi,[ebp+20]
.find_loop_eol:
        cmp esi,edi
        jae .loop_line_ready
        mov al,[esi]
        cmp al,13
        je .loop_line_ready
        cmp al,10
        je .loop_line_ready
        inc esi
        jmp .find_loop_eol
.loop_line_ready:
        mov [ebp-52],esi
        mov esi,[ebp-48]
        mov ecx,[ebp-52]
        sub ecx,esi
        call trim_span
        push keyword_loop
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jz .bad_do
        add esi,eax
        sub ecx,eax
        call trim_span
        test ecx,ecx
        jz .closing_done

        push keyword_while
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jz .check_close_until
        mov dword [ebp-36],1
        jmp .store_close_condition
.check_close_until:
        push keyword_until
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jz .bad_do
        mov dword [ebp-36],2
.store_close_condition:
        add esi,eax
        sub ecx,eax
        call trim_span
        test ecx,ecx
        jz .bad_do
        mov [ebp-28],esi
        mov [ebp-32],ecx

.closing_done:
        ; A condition may belong to DO or LOOP, but not both. A plain
        ; DO/LOOP is also valid and can be left through GOTO, STOP or END.
        cmp dword [ebp-12],0
        je .conditions_valid
        cmp dword [ebp-36],0
        jne .bad_do
.conditions_valid:
        inc dword [do_depth]
        mov dword [ebp-44],1

.loop_start:
        ; Pre-test condition, when present.
        cmp dword [ebp-12],0
        je .run_body
        mov dword [eval_work_depth],0
        push dword [ebp-8]
        push dword [ebp-4]
        call evaluate_condition
        cmp [runtime_error],0
        jne .loop_done
        cmp dword [ebp-12],1
        je .pre_while
        ; DO UNTIL: stop once condition is true.
        test eax,eax
        jnz .loop_done
        jmp .run_body
.pre_while:
        test eax,eax
        jz .loop_done

.run_body:
        inc dword [ebp-40]
        cmp dword [ebp-40],MAX_DO_ITERATIONS
        jbe .iteration_ok
        push msg_do_limit
        call set_runtime_error_z
        jmp .loop_done
.iteration_ok:
        push dword [ebp-20]
        push dword [ebp-16]
        call execute_code_block
        cmp [runtime_error],0
        jne .loop_done
        cmp dword [program_stop],0
        jne .loop_done
        cmp dword [return_pending],0
        jne .loop_done
        cmp dword [flow_pending],0
        jne .loop_done

        ; Post-test condition, when present.
        cmp dword [ebp-36],0
        je .loop_start
        mov dword [eval_work_depth],0
        push dword [ebp-32]
        push dword [ebp-28]
        call evaluate_condition
        cmp [runtime_error],0
        jne .loop_done
        cmp dword [ebp-36],1
        je .post_while
        ; LOOP UNTIL repeats while the condition is false.
        test eax,eax
        jz .loop_start
        jmp .loop_done
.post_while:
        test eax,eax
        jnz .loop_start

.loop_done:
        cmp dword [ebp-44],0
        je .handled
        dec dword [do_depth]
        mov dword [ebp-44],0
        jmp .handled

.bad_do:
        push msg_bad_do
        call set_runtime_error_z

.handled:
        mov edx,[ebp-24]
        mov eax,1
        mov esp,ebp
        pop ebp
        ret 16

; find_matching_loop(body_start,block_end)
; Returns EAX=start of matching LOOP, EDX=first byte after its EOL.
; Nested DO/LOOP pairs are counted.  EAX=0 means no matching LOOP.
find_matching_loop:
        push ebp
        mov ebp,esp
        sub esp,16
        mov esi,[ebp+8]
        mov edi,[ebp+12]
        mov dword [ebp-4],0              ; nesting level

.scan_line:
        cmp esi,edi
        jae .not_found
        mov [ebp-8],esi                  ; raw line start
        mov ebx,esi
.find_eol:
        cmp ebx,edi
        jae .line_ready
        mov al,[ebx]
        cmp al,13
        je .line_ready
        cmp al,10
        je .line_ready
        inc ebx
        jmp .find_eol
.line_ready:
        mov [ebp-12],ebx                 ; raw line end
        mov ecx,ebx
        sub ecx,esi
        call trim_span
        test ecx,ecx
        jz .advance_line
        cmp byte [esi],39
        je .advance_line

        push keyword_rem
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .advance_line

        push keyword_do
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jz .check_loop
        inc dword [ebp-4]
        jmp .advance_line

.check_loop:
        push keyword_loop
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jz .advance_line
        cmp dword [ebp-4],0
        je .found
        dec dword [ebp-4]

.advance_line:
        mov esi,[ebp-12]
.skip_eol:
        cmp esi,edi
        jae .scan_line
        mov al,[esi]
        cmp al,13
        je .inc_eol
        cmp al,10
        jne .scan_line
.inc_eol:
        inc esi
        jmp .skip_eol

.found:
        mov eax,[ebp-8]
        mov edx,[ebp-12]
.after_loop_eol:
        cmp edx,edi
        jae .return
        mov cl,[edx]
        cmp cl,13
        je .advance_loop_eol
        cmp cl,10
        jne .return
.advance_loop_eol:
        inc edx
        jmp .after_loop_eol
.return:
        mov esp,ebp
        pop ebp
        ret 8
.not_found:
        xor eax,eax
        xor edx,edx
        mov esp,ebp
        pop ebp
        ret 8

; execute_while_if_present(line_ptr,line_len,line_end,block_end)
; Returns EAX=1 when the line was WHILE and EDX points after matching WEND.
; Returns EAX=0 for an ordinary line.  The condition is reevaluated before
; every iteration, exactly as in classic BASIC.
execute_while_if_present:
        push ebp
        mov ebp,esp
        sub esp,28

        mov dword [ebp-4],0              ; condition pointer
        mov dword [ebp-8],0              ; condition length
        mov dword [ebp-12],0             ; body pointer
        mov dword [ebp-16],0             ; body length
        mov dword [ebp-20],0             ; after WEND
        mov dword [ebp-24],0             ; iteration count
        mov dword [ebp-28],0             ; depth was incremented

        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        push keyword_while
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .is_while
        xor eax,eax
        mov esp,ebp
        pop ebp
        ret 16

.is_while:
        mov edx,[while_depth]
        cmp edx,MAX_WHILE_DEPTH
        jb .depth_ok
        push msg_while_depth
        call set_runtime_error_z
        jmp .handled
.depth_ok:
        add esi,eax
        sub ecx,eax
        call trim_span
        test ecx,ecx
        jnz .condition_ok
        push msg_bad_while
        call set_runtime_error_z
        jmp .handled
.condition_ok:
        mov [ebp-4],esi
        mov [ebp-8],ecx

        ; The body starts after the WHILE line terminator(s).
        mov eax,[ebp+16]
        mov edx,[ebp+20]
.skip_while_eol:
        cmp eax,edx
        jae .body_ready
        mov cl,[eax]
        cmp cl,13
        je .advance_while_eol
        cmp cl,10
        jne .body_ready
.advance_while_eol:
        inc eax
        jmp .skip_while_eol
.body_ready:
        mov [ebp-12],eax

        push dword [ebp+20]
        push eax
        call find_matching_wend
        test eax,eax
        jnz .matching_wend
        push msg_missing_wend
        call set_runtime_error_z
        jmp .handled
.matching_wend:
        ; EAX = beginning of WEND line, EDX = first byte after WEND line.
        mov ecx,eax
        sub ecx,[ebp-12]
        mov [ebp-16],ecx
        mov [ebp-20],edx

        inc dword [while_depth]
        mov dword [ebp-28],1

.loop_test:
        mov dword [eval_work_depth],0
        push dword [ebp-8]
        push dword [ebp-4]
        call evaluate_condition
        cmp [runtime_error],0
        jne .loop_done
        test eax,eax
        jz .loop_done

        inc dword [ebp-24]
        cmp dword [ebp-24],MAX_WHILE_ITERATIONS
        jbe .iteration_ok
        push msg_while_limit
        call set_runtime_error_z
        jmp .loop_done
.iteration_ok:
        push dword [ebp-16]
        push dword [ebp-12]
        call execute_code_block
        cmp [runtime_error],0
        jne .loop_done
        cmp dword [program_stop],0
        jne .loop_done
        cmp dword [return_pending],0
        jne .loop_done
        cmp dword [flow_pending],0
        jne .loop_done
        jmp .loop_test

.loop_done:
        cmp dword [ebp-28],0
        je .handled
        dec dword [while_depth]
        mov dword [ebp-28],0

.handled:
        mov edx,[ebp-20]
        mov eax,1
        mov esp,ebp
        pop ebp
        ret 16

; find_matching_wend(body_start,block_end)
; Returns EAX=start of matching WEND, EDX=first byte after its EOL.
; Nested WHILE/WEND pairs are counted.  EAX=0 means no matching WEND.
find_matching_wend:
        push ebp
        mov ebp,esp
        sub esp,16
        mov esi,[ebp+8]
        mov edi,[ebp+12]
        mov dword [ebp-4],0              ; nesting level

.scan_line:
        cmp esi,edi
        jae .not_found
        mov [ebp-8],esi                  ; raw line start
        mov ebx,esi
.find_eol:
        cmp ebx,edi
        jae .line_ready
        mov al,[ebx]
        cmp al,13
        je .line_ready
        cmp al,10
        je .line_ready
        inc ebx
        jmp .find_eol
.line_ready:
        mov [ebp-12],ebx                 ; raw line end
        mov ecx,ebx
        sub ecx,esi
        call trim_span
        test ecx,ecx
        jz .advance_line
        cmp byte [esi],39
        je .advance_line

        push keyword_rem
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .advance_line

        push keyword_while
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jz .check_wend
        inc dword [ebp-4]
        jmp .advance_line

.check_wend:
        push keyword_wend
        push ecx
        push esi
        call equals_keyword_span
        test eax,eax
        jz .advance_line
        cmp dword [ebp-4],0
        je .found
        dec dword [ebp-4]

.advance_line:
        mov esi,[ebp-12]
.skip_eol:
        cmp esi,edi
        jae .scan_line
        mov al,[esi]
        cmp al,13
        je .inc_eol
        cmp al,10
        jne .scan_line
.inc_eol:
        inc esi
        jmp .skip_eol

.found:
        mov eax,[ebp-8]
        mov edx,[ebp-12]
.after_wend_eol:
        cmp edx,edi
        jae .return
        mov cl,[edx]
        cmp cl,13
        je .advance_wend_eol
        cmp cl,10
        jne .return
.advance_wend_eol:
        inc edx
        jmp .after_wend_eol
.return:
        mov esp,ebp
        pop ebp
        ret 8
.not_found:
        xor eax,eax
        xor edx,edx
        mov esp,ebp
        pop ebp
        ret 8

; execute_for_if_present(line_ptr,line_len,line_end,block_end)
; Returns EAX=1 when the line was FOR and EDX points after matching NEXT.
; Returns EAX=0 for an ordinary line.  FOR bodies are executed recursively,
; which naturally supports nested loops while keeping the CGI core untouched.
execute_for_if_present:
        push ebp
        mov ebp,esp
        sub esp,40

        mov dword [ebp-4],0              ; slot
        mov dword [ebp-8],0              ; current value
        mov dword [ebp-12],0             ; end value
        mov dword [ebp-16],1             ; step value
        mov dword [ebp-20],0             ; body pointer
        mov dword [ebp-24],0             ; body length
        mov dword [ebp-28],0             ; after NEXT
        mov dword [ebp-32],0             ; depth was incremented
        mov dword [ebp-36],0             ; iteration count

        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        push keyword_for
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .is_for
        xor eax,eax
        mov esp,ebp
        pop ebp
        ret 16

.is_for:
        mov edx,[for_depth]
        cmp edx,MAX_FOR_DEPTH
        jb .depth_ok
        push msg_for_depth
        call set_runtime_error_z
        jmp .handled
.depth_ok:
        mov [ebp-4],edx
        add esi,eax
        sub ecx,eax
        call trim_span

        ; Parse variable name and '='.
        push ecx
        push esi
        call find_assignment_equal
        test eax,eax
        jnz .have_equal
        push msg_bad_for
        call set_runtime_error_z
        jmp .handled
.have_equal:
        mov ebx,eax                      ; '=' pointer
        mov edx,eax
        sub edx,esi
        push edx
        push esi
        call copy_trimmed_name

        ; Keep the loop variable in its depth-specific slot.
        mov eax,[ebp-4]
        imul eax,VAR_NAME_SIZE
        lea edi,[for_names+eax]
        mov esi,var_build_name
        call copy_z_limited_name

        ; Parse start expression and locate TO.
        lea esi,[ebx+1]
        mov ecx,[ebp+8]
        add ecx,[ebp+12]
        sub ecx,esi
        call trim_span
        push keyword_to
        push ecx
        push esi
        call find_keyword_outside
        test eax,eax
        jnz .have_to
        push msg_bad_for
        call set_runtime_error_z
        jmp .handled
.have_to:
        mov ebx,eax                      ; TO pointer
        mov edx,eax
        sub edx,esi
        mov dword [eval_work_depth],0
        push eval_buffer
        push edx
        push esi
        call evaluate_atom
        cmp [runtime_error],0
        jne .handled
        mov esi,eval_buffer
        call atoi_signed
        mov [ebp-8],eax

        ; Tail after TO: end expression and optional STEP expression.
        lea esi,[ebx+2]
        mov ecx,[ebp+8]
        add ecx,[ebp+12]
        sub ecx,esi
        call trim_span
        push keyword_step
        push ecx
        push esi
        call find_keyword_outside
        test eax,eax
        jz .no_step

        mov ebx,eax                      ; STEP pointer
        mov edx,eax
        sub edx,esi
        mov dword [eval_work_depth],0
        push eval_buffer
        push edx
        push esi
        call evaluate_atom
        cmp [runtime_error],0
        jne .handled
        mov esi,eval_buffer
        call atoi_signed
        mov [ebp-12],eax

        lea esi,[ebx+4]
        mov ecx,[ebp+8]
        add ecx,[ebp+12]
        sub ecx,esi
        call trim_span
        mov dword [eval_work_depth],0
        push eval_buffer
        push ecx
        push esi
        call evaluate_atom
        cmp [runtime_error],0
        jne .handled
        mov esi,eval_buffer
        call atoi_signed
        mov [ebp-16],eax
        jmp .parsed_values

.no_step:
        mov dword [eval_work_depth],0
        push eval_buffer
        push ecx
        push esi
        call evaluate_atom
        cmp [runtime_error],0
        jne .handled
        mov esi,eval_buffer
        call atoi_signed
        mov [ebp-12],eax
        mov dword [ebp-16],1

.parsed_values:
        cmp dword [ebp-16],0
        jne .step_ok
        push msg_zero_step
        call set_runtime_error_z
        jmp .handled
.step_ok:
        ; The body starts after the FOR line terminator(s).
        mov eax,[ebp+16]
        mov edx,[ebp+20]
.skip_for_eol:
        cmp eax,edx
        jae .body_ready
        mov cl,[eax]
        cmp cl,13
        je .advance_for_eol
        cmp cl,10
        jne .body_ready
.advance_for_eol:
        inc eax
        jmp .skip_for_eol
.body_ready:
        mov [ebp-20],eax

        push dword [ebp+20]
        push eax
        call find_matching_next
        test eax,eax
        jnz .matching_next
        push msg_missing_next
        call set_runtime_error_z
        jmp .handled
.matching_next:
        ; EAX = beginning of NEXT line, EDX = first byte after NEXT line.
        mov ecx,eax
        sub ecx,[ebp-20]
        mov [ebp-24],ecx
        mov [ebp-28],edx

        ; Activate the depth slot and initialize the BASIC variable.
        inc dword [for_depth]
        mov dword [ebp-32],1
        call set_for_variable_from_current

.loop_test:
        mov eax,[ebp-16]
        test eax,eax
        js .negative_test
        mov eax,[ebp-8]
        cmp eax,[ebp-12]
        jg .loop_done
        jmp .run_body
.negative_test:
        mov eax,[ebp-8]
        cmp eax,[ebp-12]
        jl .loop_done

.run_body:
        inc dword [ebp-36]
        cmp dword [ebp-36],MAX_FOR_ITERATIONS
        jbe .iteration_ok
        push msg_for_limit
        call set_runtime_error_z
        jmp .loop_done
.iteration_ok:
        push dword [ebp-24]
        push dword [ebp-20]
        call execute_code_block
        cmp [runtime_error],0
        jne .loop_done
        cmp dword [program_stop],0
        jne .loop_done
        cmp dword [return_pending],0
        jne .loop_done
        cmp dword [flow_pending],0
        jne .loop_done

        ; BASIC increments the variable's current value, allowing the body to
        ; modify it deliberately before NEXT.
        mov eax,[ebp-4]
        imul eax,VAR_NAME_SIZE
        lea eax,[for_names+eax]
        push eax
        call get_variable_z
        test eax,eax
        jz .use_previous
        mov esi,eax
        call atoi_signed
        mov [ebp-8],eax
.use_previous:
        mov eax,[ebp-8]
        add eax,[ebp-16]
        mov [ebp-8],eax
        call set_for_variable_from_current
        jmp .loop_test

.loop_done:
        cmp dword [ebp-32],0
        je .handled
        dec dword [for_depth]
        mov dword [ebp-32],0

.handled:
        ; Always skip through the matching NEXT when one was found.  On an
        ; earlier parse error the caller will stop because runtime_error is set.
        mov edx,[ebp-28]
        mov eax,1
        mov esp,ebp
        pop ebp
        ret 16

; Uses the active execute_for_if_present frame.  Converts [ebp-8] to text and
; assigns it to the loop variable stored at slot [ebp-4].
set_for_variable_from_current:
        pushad
        mov eax,[ebp-8]
        mov edi,for_value_buffer
        call itoa_eax
        mov eax,[ebp-4]
        imul eax,VAR_NAME_SIZE
        lea eax,[for_names+eax]
        push for_value_buffer
        push eax
        call set_variable_z
        popad
        ret

; find_matching_next(body_start,block_end)
; Returns EAX=start of the matching NEXT line, EDX=first byte after its EOL.
; Nested FOR/NEXT pairs are counted.  EAX=0 means no matching NEXT.
find_matching_next:
        push ebp
        mov ebp,esp
        sub esp,16
        mov esi,[ebp+8]
        mov edi,[ebp+12]
        mov dword [ebp-4],0              ; nesting level

.scan_line:
        cmp esi,edi
        jae .not_found
        mov [ebp-8],esi                  ; raw line start
        mov ebx,esi
.find_eol:
        cmp ebx,edi
        jae .line_ready
        mov al,[ebx]
        cmp al,13
        je .line_ready
        cmp al,10
        je .line_ready
        inc ebx
        jmp .find_eol
.line_ready:
        mov [ebp-12],ebx                 ; raw line end
        mov ecx,ebx
        sub ecx,esi
        call trim_span
        test ecx,ecx
        jz .advance_line
        cmp byte [esi],39
        je .advance_line

        push keyword_rem
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .advance_line

        push keyword_for
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jz .check_next
        inc dword [ebp-4]
        jmp .advance_line

.check_next:
        push keyword_next
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jz .advance_line
        cmp dword [ebp-4],0
        je .found
        dec dword [ebp-4]

.advance_line:
        mov esi,[ebp-12]
.skip_eol:
        cmp esi,edi
        jae .scan_line
        mov al,[esi]
        cmp al,13
        je .inc_eol
        cmp al,10
        jne .scan_line
.inc_eol:
        inc esi
        jmp .skip_eol

.found:
        mov eax,[ebp-8]
        mov edx,[ebp-12]
.after_next_eol:
        cmp edx,edi
        jae .return
        mov cl,[edx]
        cmp cl,13
        je .advance_next_eol
        cmp cl,10
        jne .return
.advance_next_eol:
        inc edx
        jmp .after_next_eol
.return:
        mov esp,ebp
        pop ebp
        ret 8
.not_found:
        xor eax,eax
        xor edx,edx
        mov esp,ebp
        pop ebp
        ret 8

; execute_statement(pointer,length)
execute_statement:
        push ebp
        mov ebp,esp
        pushad
        mov dword [eval_work_depth],0
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        test ecx,ecx
        jz .done

        ; Sequential execution ignores a leading named label (NAME:) or a
        ; classic numeric line number.  The remainder of the same line, when
        ; present, is dispatched as an ordinary BASIC statement.
        call strip_statement_prefix
        test ecx,ecx
        jz .done
        mov [current_statement_ptr],esi
        mov [current_statement_len],ecx
        cmp byte [esi],39                 ; apostrophe comment
        je .done

        ; Classic BASIC shorthand: ? expression is identical to PRINT expression.
        cmp byte [esi],'?'
        jne .not_question_print
        mov eax,1
        jmp .print
.not_question_print:

        push keyword_rem
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .done

        push keyword_print
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .print

        push keyword_if
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .if_statement

        push keyword_gosub
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .gosub_statement

        push keyword_return
        push ecx
        push esi
        call equals_keyword_span
        test eax,eax
        jnz .return_statement

        push keyword_go_to
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .goto_statement

        push keyword_goto
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .goto_statement

        ; NEXT is consumed by execute_for_if_present.  Reaching it here
        ; means that the source contains an unmatched NEXT.
        push keyword_next
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .unmatched_next

        ; WEND is consumed by execute_while_if_present.  Reaching it here
        ; means that the source contains an unmatched WEND.
        push keyword_wend
        push ecx
        push esi
        call equals_keyword_span
        test eax,eax
        jnz .unmatched_wend

        ; LOOP is consumed by execute_do_if_present.  Reaching it here means
        ; the source contains a LOOP without its corresponding DO.
        push keyword_loop
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .unmatched_loop

        ; v0.1.23 runtime statements.
        push keyword_randomize
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .randomize_statement

        push keyword_sleep
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .sleep_statement

        ; v0.1.34 application composition, file I/O and native process launch.
        push keyword_include
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .include_statement

        push keyword_writefile
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .writefile_statement

        push keyword_appendfile
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .appendfile_statement

        push keyword_start
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .start_statement

        push keyword_exec
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .exec_statement

        ; v0.1.32 bounded binary image upload.
        push keyword_saveupload
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .saveupload_statement

        ; v0.1.13 control/runtime statements.
        push keyword_cls
        push ecx
        push esi
        call equals_keyword_span
        test eax,eax
        jnz .cls_statement

        push keyword_clear
        push ecx
        push esi
        call equals_keyword_span
        test eax,eax
        jnz .clear_statement

        push keyword_clr
        push ecx
        push esi
        call equals_keyword_span
        test eax,eax
        jnz .clear_statement

        push keyword_stop
        push ecx
        push esi
        call equals_keyword_span
        test eax,eax
        jnz .stop_statement

        push keyword_end
        push ecx
        push esi
        call equals_keyword_span
        test eax,eax
        jnz .stop_statement

        push keyword_input
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .input_statement

        push keyword_option_base
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .option_base_statement

        push keyword_dim
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .dim_statement

        ; DATA declarations are collected before execution and do nothing when
        ; encountered by the sequential interpreter.
        push keyword_data
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .done

        push keyword_read
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .read_statement

        push keyword_restore
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .restore_statement

        push keyword_swap
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .swap_statement

        ; Assignment: find '=' outside a string literal.
        push ecx
        push esi
        call find_assignment_equal
        test eax,eax
        jz .unsupported
        mov ebx,eax
        mov edx,eax
        sub edx,esi

        ; An assignment target may be a scalar (A or A$) or a dimensioned
        ; one-dimensional array element (A(I)).  The resolver canonicalizes
        ; array elements to names such as A(3), while leaving scalar targets
        ; on the proven v0.1.9 path.
        push assignment_name
        push edx
        push esi
        call resolve_array_reference
        cmp eax,1
        je .assignment_target_ready
        cmp eax,2
        je .done

        push edx
        push esi
        call copy_trimmed_name
        mov esi,var_build_name
        mov edi,assignment_name
        call copy_z_limited_name

.assignment_target_ready:
        mov esi,ebx
        inc esi
        mov ecx,[ebp+8]
        add ecx,[ebp+12]
        sub ecx,esi
        mov dword [eval_work_depth],0
        push eval_buffer
        push ecx
        push esi
        call evaluate_atom
        push eval_buffer
        push assignment_name
        call set_variable_z
        jmp .done

.randomize_statement:
        add esi,eax
        sub ecx,eax
        call trim_span
        test ecx,ecx
        jz .randomize_clock
        mov dword [eval_work_depth],0
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .done
        mov esi,eval_temp
        call atoi_signed
        mov [rnd_seed],eax
        jmp .done
.randomize_clock:
        push system_time
        call [GetLocalTime]
        movzx eax,word [system_time+14]
        movzx edx,word [system_time+12]
        shl edx,16
        xor eax,edx
        movzx edx,word [system_time+10]
        shl edx,8
        xor eax,edx
        or eax,1
        mov [rnd_seed],eax
        jmp .done

.sleep_statement:
        add esi,eax
        sub ecx,eax
        call trim_span
        test ecx,ecx
        jz .sleep_bad
        mov dword [eval_work_depth],0
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .done
        mov esi,eval_temp
        call parse_sleep_milliseconds
        cmp dword [runtime_error],0
        jne .done
        push eax
        call [Sleep]
        jmp .done
.sleep_bad:
        push msg_bad_sleep
        call set_runtime_error_z
        jmp .done

.include_statement:
        add esi,eax
        sub ecx,eax
        call trim_span
        push ecx
        push esi
        call execute_include
        jmp .done

.writefile_statement:
        add esi,eax
        sub ecx,eax
        call trim_span
        push 0
        push ecx
        push esi
        call execute_writefile
        jmp .done

.appendfile_statement:
        add esi,eax
        sub ecx,eax
        call trim_span
        push 1
        push ecx
        push esi
        call execute_writefile
        jmp .done

.start_statement:
        add esi,eax
        sub ecx,eax
        call trim_span
        push ecx
        push esi
        call execute_start
        jmp .done

.exec_statement:
        add esi,eax
        sub ecx,eax
        call trim_span
        push ecx
        push esi
        call execute_exec
        jmp .done

.saveupload_statement:
        add esi,eax
        sub ecx,eax
        call trim_span
        push ecx
        push esi
        call execute_saveupload
        jmp .done

.cls_statement:
        mov dword [output_length],0
        mov dword [output_truncated],0
        mov eax,[output_buffer]
        test eax,eax
        jz .done
        mov byte [eax],0
        jmp .done

.clear_statement:
        call clear_runtime_variables
        jmp .done

.stop_statement:
        mov dword [program_stop],1
        jmp .done

.input_statement:
        add esi,eax
        sub ecx,eax
        call trim_span
        push ecx
        push esi
        call execute_input
        jmp .done

.option_base_statement:
        add esi,eax
        sub ecx,eax
        call trim_span
        push ecx
        push esi
        call execute_option_base
        jmp .done

.dim_statement:
        add esi,eax
        sub ecx,eax
        call trim_span
        push ecx
        push esi
        call execute_dim
        jmp .done

.read_statement:
        add esi,eax
        sub ecx,eax
        call trim_span
        push ecx
        push esi
        call execute_read
        jmp .done

.restore_statement:
        add esi,eax
        sub ecx,eax
        call trim_span
        push ecx
        push esi
        call execute_restore
        jmp .done

.swap_statement:
        add esi,eax
        sub ecx,eax
        call trim_span
        push ecx
        push esi
        call execute_swap
        jmp .done

.print:
        ; EAX is keyword length.
        add esi,eax
        sub ecx,eax
        call trim_span
        push ecx
        push esi
        call execute_print
        jmp .done

.if_statement:
        add esi,eax
        sub ecx,eax
        call trim_span
        push ecx
        push esi
        call execute_if
        jmp .done

.gosub_statement:
        add esi,eax
        sub ecx,eax
        call trim_span
        push ecx
        push esi
        call execute_gosub
        jmp .done

.return_statement:
        cmp dword [gosub_depth],0
        je .return_without_gosub
        mov dword [return_pending],1
        jmp .done

.return_without_gosub:
        push msg_return_without_gosub
        call set_runtime_error_z
        jmp .done

.goto_statement:
        add esi,eax
        sub ecx,eax
        call trim_span
        push ecx
        push esi
        call execute_goto
        jmp .done

.unmatched_next:
        push msg_unmatched_next
        call set_runtime_error_z
        jmp .done

.unmatched_wend:
        push msg_unmatched_wend
        call set_runtime_error_z
        jmp .done

.unmatched_loop:
        push msg_unmatched_loop
        call set_runtime_error_z
        jmp .done

.unsupported:
        push msg_unsupported
        call set_runtime_error_z
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; strip_statement_prefix
; Input/output: ESI=statement pointer, ECX=length.  Removes one leading
; NAME: label or classic numeric line number and trims the remainder.
strip_statement_prefix:
        push eax
        push ebx
        push edx
        test ecx,ecx
        jz .done

        mov al,[esi]
        cmp al,'0'
        jb .named
        cmp al,'9'
        ja .named
        xor ebx,ebx
.numeric_scan:
        cmp ebx,ecx
        jae .numeric_prefix
        mov al,[esi+ebx]
        cmp al,'0'
        jb .numeric_end
        cmp al,'9'
        ja .numeric_end
        inc ebx
        jmp .numeric_scan
.numeric_end:
        mov al,[esi+ebx]
        cmp al,' '
        je .numeric_prefix
        cmp al,9
        jne .done                        ; not a valid line-number prefix
.numeric_prefix:
        add esi,ebx
        sub ecx,ebx
        call trim_span
        jmp .done

.named:
        xor ebx,ebx
.named_scan:
        cmp ebx,ecx
        jae .done
        mov al,[esi+ebx]
        cmp al,':'
        je .named_prefix
        cmp al,'A'
        jb .named_other
        cmp al,'Z'
        jbe .named_advance
        cmp al,'a'
        jb .named_other
        cmp al,'z'
        jbe .named_advance
.named_other:
        cmp al,'0'
        jb .done
        cmp al,'9'
        jbe .named_advance
        cmp al,'_'
        jne .done
.named_advance:
        inc ebx
        jmp .named_scan
.named_prefix:
        inc ebx
        add esi,ebx
        sub ecx,ebx
        call trim_span
.done:
        pop edx
        pop ebx
        pop eax
        ret

; execute_gosub(pointer,length)
; GOSUB is executed synchronously: the native interpreter call stack keeps the
; surrounding FOR/WHILE/DO context alive while the subroutine runs. RETURN
; unwinds only the nested execute_code_block invocation. This also permits
; nested GOSUB calls without storing source continuations in a separate VM stack.
execute_gosub:
        push ebp
        mov ebp,esp
        pushad
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        test ecx,ecx
        jz .bad
        cmp ecx,VAR_NAME_SIZE-1
        jae .bad

        mov edi,goto_label_name
        xor ebx,ebx
.copy_target:
        cmp ebx,ecx
        jae .target_ready
        mov al,[esi+ebx]
        mov [edi+ebx],al
        inc ebx
        jmp .copy_target
.target_ready:
        mov byte [edi+ebx],0
        push ecx
        push goto_label_name
        call find_label_target
        test eax,eax
        jz .missing

        cmp dword [gosub_depth],MAX_GOSUB_DEPTH
        jae .depth_error
        inc dword [gosub_depth]
        inc dword [gosub_call_count]
        cmp dword [gosub_call_count],MAX_GOSUB_CALLS
        ja .call_limit

        ; Run from the target to the end of the current BASIC program block.
        ; A RETURN sets return_pending, which every recursive loop executor
        ; propagates until this nested invocation regains control.
        mov edx,[active_program_end]
        sub edx,eax
        push edx
        push eax
        call execute_code_block

        cmp [runtime_error],0
        jne .leave_depth
        cmp dword [program_stop],0
        jne .leave_depth
        cmp dword [return_pending],0
        je .missing_return
        mov dword [return_pending],0
        jmp .leave_depth

.missing_return:
        push msg_missing_return
        call set_runtime_error_z
        jmp .leave_depth

.call_limit:
        push msg_gosub_limit
        call set_runtime_error_z
        jmp .leave_depth

.leave_depth:
        dec dword [gosub_depth]
        jmp .done

.depth_error:
        push msg_gosub_depth
        call set_runtime_error_z
        jmp .done
.bad:
        push msg_bad_gosub
        call set_runtime_error_z
        jmp .done
.missing:
        push msg_missing_label
        call set_runtime_error_z
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; execute_goto(pointer,length)
execute_goto:
        push ebp
        mov ebp,esp
        pushad
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        test ecx,ecx
        jz .bad
        cmp ecx,VAR_NAME_SIZE-1
        jae .bad

        mov edi,goto_label_name
        xor ebx,ebx
.copy_target:
        cmp ebx,ecx
        jae .target_ready
        mov al,[esi+ebx]
        mov [edi+ebx],al
        inc ebx
        jmp .copy_target
.target_ready:
        mov byte [edi+ebx],0
        push ecx
        push goto_label_name
        call find_label_target
        test eax,eax
        jz .missing
        mov [flow_target],eax
        mov dword [flow_pending],1
        inc dword [goto_jump_count]
        cmp dword [goto_jump_count],MAX_GOTO_JUMPS
        jbe .done
        push msg_goto_limit
        call set_runtime_error_z
        jmp .done
.bad:
        push msg_bad_goto
        call set_runtime_error_z
        jmp .done
.missing:
        push msg_missing_label
        call set_runtime_error_z
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; find_label_target(target_z,target_len) -> EAX target pointer or zero.
; Searches the active BASIC block.  Named labels use NAME:, while classic
; line numbers use a leading decimal token such as 100 PRINT "hello".
find_label_target:
        push ebp
        mov ebp,esp
        sub esp,28
        push esi
        push edi
        push ebx
        mov esi,[active_program_start]
        mov edi,[active_program_end]
        mov dword [ebp-4],0              ; raw line start
        mov dword [ebp-8],0              ; raw line end
        mov dword [ebp-12],0             ; after EOL
        mov dword [ebp-16],0             ; trimmed pointer
        mov dword [ebp-20],0             ; trimmed length
        mov dword [ebp-24],0             ; prefix length
        mov dword [ebp-28],0             ; continuation pointer
.scan_line:
        cmp esi,edi
        jae .not_found
        mov [ebp-4],esi
        mov ebx,esi
.find_eol:
        cmp ebx,edi
        jae .line_ready
        mov al,[ebx]
        cmp al,13
        je .line_ready
        cmp al,10
        je .line_ready
        inc ebx
        jmp .find_eol
.line_ready:
        mov [ebp-8],ebx
        mov edx,ebx
.skip_eol:
        cmp edx,edi
        jae .after_eol
        mov al,[edx]
        cmp al,13
        je .advance_eol
        cmp al,10
        jne .after_eol
.advance_eol:
        inc edx
        jmp .skip_eol
.after_eol:
        mov [ebp-12],edx
        mov ecx,ebx
        sub ecx,esi
        call trim_span
        mov [ebp-16],esi
        mov [ebp-20],ecx
        test ecx,ecx
        jz .advance_line
        cmp byte [esi],39
        je .advance_line

        ; Numeric line number.
        mov al,[esi]
        cmp al,'0'
        jb .named_label
        cmp al,'9'
        ja .named_label
        xor ebx,ebx
.numeric_token:
        cmp ebx,ecx
        jae .numeric_compare
        mov al,[esi+ebx]
        cmp al,'0'
        jb .numeric_boundary
        cmp al,'9'
        ja .numeric_boundary
        inc ebx
        jmp .numeric_token
.numeric_boundary:
        cmp al,' '
        je .numeric_compare
        cmp al,9
        jne .advance_line
.numeric_compare:
        mov [ebp-24],ebx
        push ebx
        push esi
        call label_span_equals_target
        test eax,eax
        jz .advance_line
        mov eax,[ebp-16]
        add eax,[ebp-24]
        mov ecx,[ebp-20]
        sub ecx,[ebp-24]
        mov esi,eax
        call trim_span
        test ecx,ecx
        jnz .found_pointer
        mov eax,[ebp-12]
        jmp .found

.named_label:
        xor ebx,ebx
.named_token:
        cmp ebx,ecx
        jae .advance_line
        mov al,[esi+ebx]
        cmp al,':'
        je .named_compare
        cmp al,'A'
        jb .named_other
        cmp al,'Z'
        jbe .named_next
        cmp al,'a'
        jb .named_other
        cmp al,'z'
        jbe .named_next
.named_other:
        cmp al,'0'
        jb .advance_line
        cmp al,'9'
        jbe .named_next
        cmp al,'_'
        jne .advance_line
.named_next:
        inc ebx
        jmp .named_token
.named_compare:
        mov [ebp-24],ebx
        push ebx
        push esi
        call label_span_equals_target
        test eax,eax
        jz .advance_line
        mov eax,[ebp-16]
        add eax,[ebp-24]
        inc eax                           ; skip ':'
        mov ecx,[ebp-20]
        sub ecx,[ebp-24]
        dec ecx
        mov esi,eax
        call trim_span
        test ecx,ecx
        jnz .found_pointer
        mov eax,[ebp-12]
        jmp .found
.found_pointer:
        mov eax,esi
.found:
        jmp .return
.advance_line:
        mov esi,[ebp-12]
        jmp .scan_line
.not_found:
        xor eax,eax
.return:
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 8

; label_span_equals_target(pointer,length) -> EAX boolean, case-insensitive.
label_span_equals_target:
        push ebp
        mov ebp,esp
        push esi
        push edi
        push ebx
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        mov edi,goto_label_name
        xor ebx,ebx
.compare:
        cmp ebx,ecx
        jae .target_end
        mov al,[esi+ebx]
        mov ah,[edi+ebx]
        test ah,ah
        jz .no
        cmp al,'a'
        jb .left_ok
        cmp al,'z'
        ja .left_ok
        sub al,20h
.left_ok:
        cmp ah,'a'
        jb .right_ok
        cmp ah,'z'
        ja .right_ok
        sub ah,20h
.right_ok:
        cmp al,ah
        jne .no
        inc ebx
        jmp .compare
.target_end:
        cmp byte [edi+ebx],0
        jne .no
        mov eax,1
        jmp .done
.no:
        xor eax,eax
.done:
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 8

; try_print_directive(pointer,length) -> EAX=1 when consumed.
; Supported compatibility directives:
;   PRINT "@@STATUS 201"
;   PRINT "@@CONTENT-TYPE application/json; charset=utf-8"
;   PRINT "@@HEADER Cache-Control: no-store"
; Header values are rejected when they contain CR/LF, preventing response
; splitting even when a generated source line is malformed.
try_print_directive:
        push ebp
        mov ebp,esp
        push esi
        push edi
        push ebx
        push ecx
        push edx
        xor eax,eax

        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        ; trim_span uses AL while examining whitespace. Reset EAX here so
        ; every early non-directive exit returns a strict false value.
        xor eax,eax
        cmp ecx,4
        jb .done
        cmp byte [esi],'"'
        jne .done
        mov edx,esi
        add edx,ecx
        dec edx
        cmp byte [edx],'"'
        jne .done
        cmp byte [esi+1],'@'
        jne .done
        cmp byte [esi+2],'@'
        jne .done

        inc esi
        sub ecx,2
        cmp ecx,DIRECTIVE_SIZE-1
        jbe .copy
        push msg_directive_large
        call set_runtime_error_z
        mov eax,1
        jmp .done
.copy:
        mov edi,directive_buffer
        rep movsb
        mov byte [edi],0

        mov esi,directive_buffer
        mov edi,directive_status_prefix
        call starts_with_i
        test eax,eax
        jnz .status

        mov esi,directive_buffer
        mov edi,directive_content_type_prefix
        call starts_with_i
        test eax,eax
        jnz .content_type

        mov esi,directive_buffer
        mov edi,directive_header_prefix
        call starts_with_i
        test eax,eax
        jnz .header

        xor eax,eax
        jmp .done

.status:
        mov esi,directive_buffer+directive_status_prefix_len
        call skip_spaces_esi
        cmp byte [esi],0
        je .bad_status
        call atoi_unsigned
        cmp eax,100
        jb .bad_status
        cmp eax,599
        ja .bad_status
        mov [response_status_code],eax
        call build_response_status_line
        mov eax,1
        jmp .done
.bad_status:
        push msg_bad_status_directive
        call set_runtime_error_z
        mov eax,1
        jmp .done

.content_type:
        mov esi,directive_buffer+directive_content_type_prefix_len
        call skip_spaces_esi
        cmp byte [esi],0
        je .bad_content_type
        mov edi,response_content_type
        mov ecx,CONTENT_TYPE_SIZE-1
.ct_copy:
        mov al,[esi]
        test al,al
        jz .ct_done
        cmp al,13
        je .bad_content_type
        cmp al,10
        je .bad_content_type
        test ecx,ecx
        jz .content_type_large
        stosb
        inc esi
        dec ecx
        jmp .ct_copy
.ct_done:
        mov byte [edi],0
        mov eax,1
        jmp .done
.bad_content_type:
        push msg_bad_content_type_directive
        call set_runtime_error_z
        mov eax,1
        jmp .done
.content_type_large:
        push msg_content_type_large
        call set_runtime_error_z
        mov eax,1
        jmp .done

.header:
        mov esi,directive_buffer+directive_header_prefix_len
        call skip_spaces_esi
        cmp byte [esi],0
        je .bad_header
        mov ebx,esi
        xor edx,edx                    ; colon seen
.header_scan:
        mov al,[esi]
        test al,al
        jz .header_scanned
        cmp al,13
        je .bad_header
        cmp al,10
        je .bad_header
        cmp al,':'
        jne .header_advance
        mov edx,1
.header_advance:
        inc esi
        jmp .header_scan
.header_scanned:
        test edx,edx
        jz .bad_header
        mov esi,ebx
        call strlen_esi
        mov ecx,eax
        mov edx,[response_custom_headers_length]
        mov eax,edx
        add eax,ecx
        add eax,2
        cmp eax,MAX_CUSTOM_HEADERS
        ja .headers_large
        mov edi,response_custom_headers
        add edi,edx
        rep movsb
        mov byte [edi],13
        mov byte [edi+1],10
        add edi,2
        mov byte [edi],0
        mov [response_custom_headers_length],eax
        mov eax,1
        jmp .done
.bad_header:
        push msg_bad_header_directive
        call set_runtime_error_z
        mov eax,1
        jmp .done
.headers_large:
        push msg_headers_large
        call set_runtime_error_z
        mov eax,1
.done:
        pop edx
        pop ecx
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 8

; Build a CGI Status header from response_status_code. The common HTTP reason
; phrases are supplied for compatibility with Apache on Windows.
build_response_status_line:
        pushad
        mov edi,response_status_line
        mov esi,status_header_prefix
        mov ecx,status_header_prefix_len
        rep movsb
        mov eax,[response_status_code]
        call utoa_eax
        mov byte [edi],' '
        inc edi

        mov eax,[response_status_code]
        mov ebx,status_reason_custom
        cmp eax,200
        je .ok
        cmp eax,201
        je .created
        cmp eax,204
        je .no_content
        cmp eax,301
        je .moved
        cmp eax,302
        je .found
        cmp eax,400
        je .bad_request
        cmp eax,401
        je .unauthorized
        cmp eax,403
        je .forbidden
        cmp eax,404
        je .not_found
        cmp eax,409
        je .conflict
        cmp eax,422
        je .unprocessable
        cmp eax,429
        je .too_many
        cmp eax,500
        je .internal
        cmp eax,503
        je .unavailable
        jmp .copy_reason
.ok:            mov ebx,status_reason_ok
                jmp .copy_reason
.created:       mov ebx,status_reason_created
                jmp .copy_reason
.no_content:    mov ebx,status_reason_no_content
                jmp .copy_reason
.moved:         mov ebx,status_reason_moved
                jmp .copy_reason
.found:         mov ebx,status_reason_found
                jmp .copy_reason
.bad_request:   mov ebx,status_reason_bad_request
                jmp .copy_reason
.unauthorized:  mov ebx,status_reason_unauthorized
                jmp .copy_reason
.forbidden:     mov ebx,status_reason_forbidden
                jmp .copy_reason
.not_found:     mov ebx,status_reason_not_found
                jmp .copy_reason
.conflict:      mov ebx,status_reason_conflict
                jmp .copy_reason
.unprocessable: mov ebx,status_reason_unprocessable
                jmp .copy_reason
.too_many:      mov ebx,status_reason_too_many
                jmp .copy_reason
.internal:      mov ebx,status_reason_internal
                jmp .copy_reason
.unavailable:   mov ebx,status_reason_unavailable
.copy_reason:
        call copy_z_advance_nozero
        mov byte [edi],13
        mov byte [edi+1],10
        add edi,2
        mov byte [edi],0
        sub edi,response_status_line
        mov [response_status_line_length],edi
        popad
        ret

; execute_input(pointer,length)
; INPUT is deliberately unavailable under Apache CGI because stdin contains the
; HTTP request body.  During direct execution (REQUEST_METHOD absent), it reads
; one line from standard input.  Supported forms:
;     INPUT A$
;     INPUT "Name"; A$
;     INPUT "Age", A
; Scalar and one-dimensional array-element targets are accepted.
execute_input:
        push ebp
        mov ebp,esp
        pushad
        cmp dword [cgi_mode],0
        jne .cgi_disabled

        ; Direct mode is interactive: flush output generated before INPUT so
        ; prompts and preceding PRINT statements are visible immediately.
        cmp dword [output_length],0
        je .pending_output_flushed
        push dword [output_length]
        push dword [output_buffer]
        call raw_stdout_write
        mov dword [output_length],0
        mov eax,[output_buffer]
        mov byte [eax],0
.pending_output_flushed:

        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        test ecx,ecx
        jz .bad_syntax
        mov [input_span_start],esi
        mov [input_span_length],ecx

        ; Locate an optional prompt separator outside quoted text.
        push token_semicolon
        push ecx
        push esi
        call find_token_outside
        test eax,eax
        jnz .have_prompt
        push token_comma
        push ecx
        push esi
        call find_token_outside
        test eax,eax
        jz .target_without_prompt

.have_prompt:
        mov ebx,eax                    ; separator address
        mov edx,eax
        sub edx,esi                    ; prompt expression length
        push eval_temp
        push edx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .done
        push eax
        push eval_temp
        call raw_stdout_write

        mov esi,ebx
        inc esi
        mov ecx,[input_span_start]
        add ecx,[input_span_length]
        sub ecx,esi
        call trim_span
        test ecx,ecx
        jz .bad_syntax
        jmp .resolve_target

.target_without_prompt:
        mov esi,[input_span_start]
        mov ecx,[input_span_length]

.resolve_target:
        mov ebx,esi
        mov edx,ecx
        push input_name
        push edx
        push ebx
        call resolve_array_reference
        cmp eax,1
        je .target_ready
        cmp eax,2
        je .done
        push edx
        push ebx
        call copy_trimmed_name
        cmp byte [var_build_name],0
        je .bad_syntax
        mov esi,var_build_name
        mov edi,input_name
        call copy_z_limited_name

.target_ready:
        push STD_INPUT_HANDLE
        call [GetStdHandle]
        mov [stdin_handle],eax
        cmp eax,INVALID_HANDLE_VALUE
        je .read_failed

        xor edi,edi
.read_loop:
        push 0
        push input_bytes
        push 1
        push input_char
        push dword [stdin_handle]
        call [ReadFile]
        test eax,eax
        jz .read_complete
        cmp dword [input_bytes],0
        je .read_complete

        mov al,[input_char]
        cmp dword [input_skip_lf],0
        je .normal_char
        mov dword [input_skip_lf],0
        cmp al,10
        je .read_loop
.normal_char:
        cmp al,13
        jne .check_lf
        mov dword [input_skip_lf],1
        jmp .read_complete
.check_lf:
        cmp al,10
        je .read_complete
        cmp edi,VAR_VALUE_SIZE-1
        jae .read_loop                  ; drain an overlong line safely
        mov [input_buffer+edi],al
        inc edi
        jmp .read_loop

.read_complete:
        mov byte [input_buffer+edi],0
        push input_buffer
        push input_name
        call set_variable_z
        jmp .done

.cgi_disabled:
        push msg_input_cgi
        call set_runtime_error_z
        jmp .done
.bad_syntax:
        push msg_bad_input
        call set_runtime_error_z
        jmp .done
.read_failed:
        push msg_input_read
        call set_runtime_error_z
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; execute_saveupload(pointer,length)
; Saves the exact CGI request body to <script-directory>\uploads\<filename>.
; The filename is supplied as a BASIC expression and is deliberately restricted
; to a basename containing letters, digits, underscore, hyphen and dots.  Only
; PNG/JPG/JPEG/GIF/WEBP extensions are accepted.  Normal upload failures are
; reported through BASIC variables so a JSON/HTML endpoint can respond cleanly:
;   UPLOAD_OK, UPLOAD_SIZE, UPLOAD_NAME$, UPLOAD_FILE$, UPLOAD_URL$, UPLOAD_ERROR$
execute_saveupload:
        push ebp
        mov ebp,esp
        pushad
        call reset_upload_variables

        cmp dword [cgi_mode],0
        jne .cgi_ok
        push upload_err_cgi
        call set_upload_error_z
        jmp .done
.cgi_ok:
        cmp dword [request_body_advertised_length],MAX_BODY
        jbe .size_ok
        push upload_err_too_large
        call set_upload_error_z
        jmp .done
.size_ok:
        cmp dword [request_body_length],0
        jne .body_ok
        push upload_err_empty
        call set_upload_error_z
        jmp .done
.body_ok:
        ; Accept the tutorial's raw binary transport and direct image MIME types.
        push ENV_SIZE
        push env_buffer
        push env_content_type
        call [GetEnvironmentVariableA]
        cmp eax,ENV_SIZE
        jb .content_length_ok
        mov eax,ENV_SIZE-1
.content_length_ok:
        mov byte [env_buffer+eax],0
        mov esi,env_buffer
        mov edi,mime_octet_stream
        call starts_with_i
        test eax,eax
        jnz .content_ok
        mov esi,env_buffer
        mov edi,mime_image_prefix
        call starts_with_i
        test eax,eax
        jnz .content_ok
        push upload_err_content_type
        call set_upload_error_z
        jmp .done

.content_ok:
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        test ecx,ecx
        jnz .have_expression
        push msg_bad_saveupload
        call set_runtime_error_z
        jmp .done
.have_expression:
        mov dword [eval_work_depth],0
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .done
        cmp byte [eval_temp],0
        jne .validate_name
        push upload_err_filename
        call set_upload_error_z
        jmp .done
.validate_name:
        mov esi,eval_temp
        call validate_upload_filename_z
        test eax,eax
        jnz .validate_signature
        push upload_err_filename
        call set_upload_error_z
        jmp .done

.validate_signature:
        call validate_upload_signature
        test eax,eax
        jnz .build_paths
        push upload_err_signature
        call set_upload_error_z
        jmp .done

.build_paths:
        call build_upload_paths
        test eax,eax
        jnz .directory
        push upload_err_path
        call set_upload_error_z
        jmp .done

.directory:
        ; Creating an existing directory returns zero; that is harmless because
        ; CreateFileA below is the authoritative accessibility check.
        push 0
        push upload_directory
        call [CreateDirectoryA]

        push 0
        push FILE_ATTRIBUTE_NORMAL
        push CREATE_ALWAYS
        push 0
        push 0
        push GENERIC_WRITE
        push upload_full_path
        call [CreateFileA]
        cmp eax,INVALID_HANDLE_VALUE
        jne .opened
        push upload_err_open
        call set_upload_error_z
        jmp .done
.opened:
        mov [upload_handle],eax
        xor edi,edi
.write_more:
        mov eax,[request_body_length]
        sub eax,edi
        jz .write_complete
        push 0
        push bytes_done
        push eax
        mov edx,[body_buffer]
        add edx,edi
        push edx
        push dword [upload_handle]
        call [WriteFile]
        test eax,eax
        jz .write_failed
        mov eax,[bytes_done]
        test eax,eax
        jz .write_failed
        add edi,eax
        jmp .write_more

.write_failed:
        push dword [upload_handle]
        call [CloseHandle]
        mov dword [upload_handle],INVALID_HANDLE_VALUE
        push upload_full_path
        call [DeleteFileA]
        push upload_err_write
        call set_upload_error_z
        jmp .done

.write_complete:
        push dword [upload_handle]
        call [CloseHandle]
        mov dword [upload_handle],INVALID_HANDLE_VALUE

        push upload_text_one
        push var_upload_ok
        call set_variable_z

        mov eax,[request_body_length]
        mov edi,upload_size_text
        call utoa_eax
        push upload_size_text
        push var_upload_size
        call set_variable_z

        push eval_temp
        push var_upload_name
        call set_variable_z
        push upload_full_path
        push var_upload_file
        call set_variable_z
        push upload_public_url
        push var_upload_url
        call set_variable_z
        push upload_text_empty
        push var_upload_error
        call set_variable_z
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; Initialise the public upload result variables before every SAVEUPLOAD call.
reset_upload_variables:
        push upload_text_zero
        push var_upload_ok
        call set_variable_z
        push upload_text_zero
        push var_upload_size
        call set_variable_z
        push upload_text_empty
        push var_upload_name
        call set_variable_z
        push upload_text_empty
        push var_upload_file
        call set_variable_z
        push upload_text_empty
        push var_upload_url
        call set_variable_z
        push upload_text_empty
        push var_upload_error
        call set_variable_z
        ret

; set_upload_error_z(message)
set_upload_error_z:
        push ebp
        mov ebp,esp
        push upload_text_zero
        push var_upload_ok
        call set_variable_z
        push dword [ebp+8]
        push var_upload_error
        call set_variable_z
        mov esp,ebp
        pop ebp
        ret 4

; ESI -> filename, EAX=1 when it is a safe supported image basename.
validate_upload_filename_z:
        push ebx
        push ecx
        push edx
        push edi
        push esi
        mov ebx,esi                         ; filename start
        xor ecx,ecx                         ; length
        xor edx,edx                         ; last dot address
        xor edi,edi                         ; previous-was-dot flag
.scan:
        mov al,[esi]
        test al,al
        jz .scanned
        inc ecx
        cmp ecx,MAX_UPLOAD_FILENAME
        ja .invalid

        cmp al,'.'
        jne .not_dot
        test edi,edi
        jnz .invalid                        ; reject ".." anywhere
        mov edx,esi
        mov edi,1
        inc esi
        jmp .scan
.not_dot:
        xor edi,edi
        cmp al,'0'
        jb .check_upper
        cmp al,'9'
        jbe .accepted
.check_upper:
        cmp al,'A'
        jb .check_lower
        cmp al,'Z'
        jbe .accepted
.check_lower:
        cmp al,'a'
        jb .check_punctuation
        cmp al,'z'
        jbe .accepted
.check_punctuation:
        cmp al,'_'
        je .accepted
        cmp al,'-'
        je .accepted
        jmp .invalid
.accepted:
        inc esi
        jmp .scan

.scanned:
        test ecx,ecx
        jz .invalid
        test edx,edx
        jz .invalid
        cmp edx,ebx
        je .invalid                         ; no hidden/extension-only names
        cmp byte [edx+1],0
        je .invalid
        lea esi,[edx+1]
        mov edi,upload_ext_png
        call strings_equal_z
        test eax,eax
        jnz .valid
        lea esi,[edx+1]
        mov edi,upload_ext_jpg
        call strings_equal_z
        test eax,eax
        jnz .valid
        lea esi,[edx+1]
        mov edi,upload_ext_jpeg
        call strings_equal_z
        test eax,eax
        jnz .valid
        lea esi,[edx+1]
        mov edi,upload_ext_gif
        call strings_equal_z
        test eax,eax
        jnz .valid
        lea esi,[edx+1]
        mov edi,upload_ext_webp
        call strings_equal_z
        test eax,eax
        jnz .valid
.invalid:
        xor eax,eax
        jmp .finish
.valid:
        mov eax,1
.finish:
        pop esi
        pop edi
        pop edx
        pop ecx
        pop ebx
        ret

; Validate the request-body magic bytes against the accepted extension.
; This does not attempt full image decoding, but blocks ordinary renamed files.
validate_upload_signature:
        push ebx
        push ecx
        push edx
        push esi
        push edi
        mov esi,eval_temp
        xor edx,edx
.find_dot:
        mov al,[esi]
        test al,al
        jz .have_extension
        cmp al,'.'
        jne .next_char
        lea edx,[esi+1]
.next_char:
        inc esi
        jmp .find_dot
.have_extension:
        test edx,edx
        jz .invalid
        mov esi,edx
        mov edi,upload_ext_png
        call strings_equal_z
        test eax,eax
        jnz .png
        mov esi,edx
        mov edi,upload_ext_jpg
        call strings_equal_z
        test eax,eax
        jnz .jpeg
        mov esi,edx
        mov edi,upload_ext_jpeg
        call strings_equal_z
        test eax,eax
        jnz .jpeg
        mov esi,edx
        mov edi,upload_ext_gif
        call strings_equal_z
        test eax,eax
        jnz .gif
        mov esi,edx
        mov edi,upload_ext_webp
        call strings_equal_z
        test eax,eax
        jnz .webp
        jmp .invalid
.png:
        cmp dword [request_body_length],8
        jb .invalid
        mov ebx,[body_buffer]
        cmp byte [ebx],089h
        jne .invalid
        cmp byte [ebx+1],050h
        jne .invalid
        cmp byte [ebx+2],04Eh
        jne .invalid
        cmp byte [ebx+3],047h
        jne .invalid
        cmp byte [ebx+4],00Dh
        jne .invalid
        cmp byte [ebx+5],00Ah
        jne .invalid
        cmp byte [ebx+6],01Ah
        jne .invalid
        cmp byte [ebx+7],00Ah
        jne .invalid
        jmp .valid
.jpeg:
        cmp dword [request_body_length],3
        jb .invalid
        mov ebx,[body_buffer]
        cmp byte [ebx],0FFh
        jne .invalid
        cmp byte [ebx+1],0D8h
        jne .invalid
        cmp byte [ebx+2],0FFh
        jne .invalid
        jmp .valid
.gif:
        cmp dword [request_body_length],6
        jb .invalid
        mov ebx,[body_buffer]
        cmp byte [ebx],'G'
        jne .invalid
        cmp byte [ebx+1],'I'
        jne .invalid
        cmp byte [ebx+2],'F'
        jne .invalid
        cmp byte [ebx+3],'8'
        jne .invalid
        mov al,[ebx+4]
        cmp al,'7'
        je .gif_version_ok
        cmp al,'9'
        jne .invalid
.gif_version_ok:
        cmp byte [ebx+5],'a'
        jne .invalid
        jmp .valid
.webp:
        cmp dword [request_body_length],12
        jb .invalid
        mov ebx,[body_buffer]
        cmp byte [ebx],'R'
        jne .invalid
        cmp byte [ebx+1],'I'
        jne .invalid
        cmp byte [ebx+2],'F'
        jne .invalid
        cmp byte [ebx+3],'F'
        jne .invalid
        cmp byte [ebx+8],'W'
        jne .invalid
        cmp byte [ebx+9],'E'
        jne .invalid
        cmp byte [ebx+10],'B'
        jne .invalid
        cmp byte [ebx+11],'P'
        jne .invalid
.valid:
        mov eax,1
        jmp .done
.invalid:
        xor eax,eax
.done:
        pop edi
        pop esi
        pop edx
        pop ecx
        pop ebx
        ret

; Build upload_directory, upload_full_path and upload_public_url.
; Returns EAX=1 on success, zero if the script path leaves insufficient room.
build_upload_paths:
        push ebx
        push ecx
        push edx
        push esi
        push edi
        mov esi,script_path
        xor edx,edx                         ; address after last separator
.find_separator:
        mov al,[esi]
        test al,al
        jz .separator_done
        cmp al,'\'
        je .remember
        cmp al,'/'
        jne .separator_next
.remember:
        lea edx,[esi+1]
.separator_next:
        inc esi
        jmp .find_separator
.separator_done:
        mov edi,upload_directory
        test edx,edx
        jz .relative_directory

        mov ecx,edx
        sub ecx,script_path                 ; include final separator
        cmp ecx,PATH_SIZE-160
        jae .failure
        mov esi,script_path
        rep movsb
        mov ebx,upload_directory_leaf
        call copy_z_advance
        jmp .directory_ready
.relative_directory:
        mov ebx,upload_directory_relative
        call copy_z_advance
.directory_ready:
        ; Full server-side path.
        mov ebx,upload_directory
        mov edi,upload_full_path
        call copy_z_advance
        mov byte [edi],'\'
        inc edi
        mov ebx,eval_temp
        call copy_z_advance

        ; Relative browser URL, deliberately independent of filesystem paths.
        mov ebx,upload_url_prefix
        mov edi,upload_public_url
        call copy_z_advance
        mov ebx,eval_temp
        call copy_z_advance
        mov eax,1
        jmp .done
.failure:
        xor eax,eax
.done:
        pop edi
        pop esi
        pop edx
        pop ecx
        pop ebx
        ret

; ----------------------------------------------------------------------------
; v0.1.34 application composition, file I/O and native process launch
; ----------------------------------------------------------------------------

; validate_relative_path_z(ESI) -> EAX=1 for a bounded relative path.
; Absolute paths, drive names, traversal, wildcards and control characters are
; rejected. Forward slashes are accepted and normalized when the full path is built.
validate_relative_path_z:
        push ebx
        push ecx
        push edx
        push edi
        push esi
        xor ecx,ecx
        xor edx,edx                     ; previous dot
        mov al,[esi]
        test al,al
        jz .invalid
        cmp al,'\'
        je .invalid
        cmp al,'/'
        je .invalid
.scan:
        mov al,[esi]
        test al,al
        jz .finish
        inc ecx
        cmp ecx,PATH_SIZE-256
        jae .invalid
        cmp al,32
        jb .invalid
        cmp al,':'
        je .invalid
        cmp al,'*'
        je .invalid
        cmp al,'?'
        je .invalid
        cmp al,'"'
        je .invalid
        cmp al,'<'
        je .invalid
        cmp al,'>'
        je .invalid
        cmp al,'|'
        je .invalid
        cmp al,'.'
        jne .not_dot
        test edx,edx
        jnz .invalid                    ; reject ".." anywhere
        mov edx,1
        inc esi
        jmp .scan
.not_dot:
        xor edx,edx
        inc esi
        jmp .scan
.finish:
        test ecx,ecx
        jz .invalid
        mov eax,1
        jmp .done
.invalid:
        xor eax,eax
.done:
        pop esi
        pop edi
        pop edx
        pop ecx
        pop ebx
        ret

; build_app_path_z(input_z,output_z) -> EAX=1 on success.
; Every path is rooted beside the main requested .bas file.
build_app_path_z:
        push ebp
        mov ebp,esp
        push ebx
        push ecx
        push edx
        push esi
        push edi
        mov esi,[ebp+8]
        call validate_relative_path_z
        test eax,eax
        jz .failure
        mov esi,script_path
        xor edx,edx
.find_sep:
        mov al,[esi]
        test al,al
        jz .sep_done
        cmp al,'\'
        je .remember
        cmp al,'/'
        jne .next
.remember:
        lea edx,[esi+1]
.next:
        inc esi
        jmp .find_sep
.sep_done:
        mov edi,[ebp+12]
        test edx,edx
        jz .copy_relative
        mov ecx,edx
        sub ecx,script_path
        cmp ecx,PATH_SIZE-256
        jae .failure
        mov esi,script_path
        rep movsb
.copy_relative:
        mov esi,[ebp+8]
.copy:
        mov al,[esi]
        test al,al
        jz .terminate
        cmp al,'/'
        jne .store
        mov al,'\'
.store:
        stosb
        inc esi
        jmp .copy
.terminate:
        mov byte [edi],0
        mov eax,1
        jmp .done
.failure:
        xor eax,eax
.done:
        pop edi
        pop esi
        pop edx
        pop ecx
        pop ebx
        mov esp,ebp
        pop ebp
        ret 8

; case-insensitive extension helpers. ESI is a zero-terminated path.
path_extension_z:
        push ebx
        xor ebx,ebx
.scan:
        mov al,[esi]
        test al,al
        jz .done
        cmp al,'.'
        jne .next
        lea ebx,[esi+1]
.next:
        inc esi
        jmp .scan
.done:
        mov eax,ebx
        pop ebx
        ret

is_include_extension_z:
        push esi
        call path_extension_z
        test eax,eax
        jz .no
        mov esi,eax
        mov edi,ext_bas
        call strings_equal_z
        test eax,eax
        jnz .yes
        pop esi
        push esi
        call path_extension_z
        mov esi,eax
        mov edi,ext_inc
        call strings_equal_z
        test eax,eax
        jnz .yes
.no:
        xor eax,eax
        pop esi
        ret
.yes:
        mov eax,1
        pop esi
        ret

; WRITEFILE/APPENDFILE may write only below data/ and never server-side code.
is_writable_data_path_z:
        push esi
        mov edi,prefix_data_forward
        call starts_with_z_ci
        test eax,eax
        jnz .prefix_ok
        pop esi
        push esi
        mov edi,prefix_data_back
        call starts_with_z_ci
        test eax,eax
        jz .no_pop
.prefix_ok:
        pop esi
        push esi
        call path_extension_z
        test eax,eax
        jz .no_pop
        mov esi,eax
        mov edi,ext_bas
        call strings_equal_z
        test eax,eax
        jnz .no_pop
        pop esi
        push esi
        call path_extension_z
        mov esi,eax
        mov edi,ext_inc
        call strings_equal_z
        test eax,eax
        jnz .no_pop
        pop esi
        mov eax,1
        ret
.no_pop:
        pop esi
        xor eax,eax
        ret

; starts_with_z_ci: ESI text, EDI prefix -> EAX boolean.
starts_with_z_ci:
        push esi
        push edi
.loop:
        mov al,[edi]
        test al,al
        jz .yes
        mov ah,[esi]
        test ah,ah
        jz .no
        or al,20h
        or ah,20h
        cmp al,ah
        jne .no
        inc esi
        inc edi
        jmp .loop
.yes:
        mov eax,1
        jmp .done
.no:
        xor eax,eax
.done:
        pop edi
        pop esi
        ret

; execute_include(pointer,length)
execute_include:
        push ebp
        mov ebp,esp
        pushad
        mov dword [include_handle],INVALID_HANDLE_VALUE
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        test ecx,ecx
        jz .bad_syntax
        cmp dword [include_depth],MAX_INCLUDE_DEPTH
        jae .depth_error
        mov dword [eval_work_depth],0
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .done
        mov esi,eval_temp
        call validate_relative_path_z
        test eax,eax
        jz .bad_path
        mov esi,eval_temp
        call is_include_extension_z
        test eax,eax
        jz .bad_extension
        push include_full_path
        push eval_temp
        call build_app_path_z
        test eax,eax
        jz .bad_path

        push 0
        push FILE_ATTRIBUTE_NORMAL
        push OPEN_EXISTING
        push 0
        push FILE_SHARE_READ
        push GENERIC_READ
        push include_full_path
        call [CreateFileA]
        cmp eax,INVALID_HANDLE_VALUE
        je .open_error
        mov [include_handle],eax
        push file_size64
        push eax
        call [GetFileSizeEx]
        test eax,eax
        jz .size_error
        cmp dword [file_size64+4],0
        jne .too_large
        mov eax,dword [file_size64]
        cmp eax,MAX_INCLUDE_SIZE-1
        ja .too_large
        mov [include_length],eax

        mov ecx,[include_depth]
        imul ecx,MAX_INCLUDE_SIZE
        lea edi,[include_buffers+ecx]
        mov [include_current_buffer],edi
        push 0
        push bytes_done
        push dword [include_length]
        push edi
        push dword [include_handle]
        call [ReadFile]
        test eax,eax
        jz .read_error
        mov eax,[bytes_done]
        cmp eax,[include_length]
        jne .read_error
        mov edi,[include_current_buffer]
        add edi,eax
        mov byte [edi],0
        push dword [include_handle]
        call [CloseHandle]
        mov dword [include_handle],INVALID_HANDLE_VALUE

        ; Save the caller's DATA/READ context into the depth-specific backup.
        mov eax,[include_depth]
        mov edx,eax
        shl edx,2
        mov ecx,[data_item_count]
        mov [include_saved_data_count+edx],ecx
        mov ecx,[data_read_index]
        mov [include_saved_data_index+edx],ecx
        mov ecx,[data_initialized]
        mov [include_saved_data_initialized+edx],ecx
        imul eax,MAX_DATA_ITEMS*DATA_ITEM_SIZE
        lea edi,[include_data_backups+eax]
        mov esi,data_items
        mov ecx,(MAX_DATA_ITEMS*DATA_ITEM_SIZE)/4
        rep movsd

        inc dword [include_depth]
        push dword [include_length]
        push dword [include_current_buffer]
        call execute_source_span
        dec dword [include_depth]

        ; Restore the caller's DATA/READ context even when included code fails.
        mov eax,[include_depth]
        mov edx,eax
        shl edx,2
        mov ecx,[include_saved_data_count+edx]
        mov [data_item_count],ecx
        mov ecx,[include_saved_data_index+edx]
        mov [data_read_index],ecx
        mov ecx,[include_saved_data_initialized+edx]
        mov [data_initialized],ecx
        imul eax,MAX_DATA_ITEMS*DATA_ITEM_SIZE
        lea esi,[include_data_backups+eax]
        mov edi,data_items
        mov ecx,(MAX_DATA_ITEMS*DATA_ITEM_SIZE)/4
        rep movsd
        jmp .done

.bad_syntax:
        push msg_bad_include
        call set_runtime_error_z
        jmp .done
.depth_error:
        push msg_include_depth
        call set_runtime_error_z
        jmp .done
.bad_path:
        push msg_include_path
        call set_runtime_error_z
        jmp .done
.bad_extension:
        push msg_include_extension
        call set_runtime_error_z
        jmp .done
.open_error:
        push msg_include_open
        call set_runtime_error_z
        jmp .done
.size_error:
        push msg_include_size
        call set_runtime_error_z
        jmp .close_done
.too_large:
        push msg_include_large
        call set_runtime_error_z
        jmp .close_done
.read_error:
        push msg_include_read
        call set_runtime_error_z
.close_done:
        cmp dword [include_handle],INVALID_HANDLE_VALUE
        je .done
        push dword [include_handle]
        call [CloseHandle]
        mov dword [include_handle],INVALID_HANDLE_VALUE
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; reset FILE_* result variables.
reset_file_variables:
        push text_zero
        push var_file_ok
        call set_variable_z
        push text_zero
        push var_file_size
        call set_variable_z
        push text_empty
        push var_file_path
        call set_variable_z
        push text_empty
        push var_file_error
        call set_variable_z
        ret

set_file_error_z:
        push ebp
        mov ebp,esp
        push text_zero
        push var_file_ok
        call set_variable_z
        push dword [ebp+8]
        push var_file_error
        call set_variable_z
        mov esp,ebp
        pop ebp
        ret 4

; execute_writefile(pointer,length,append_mode)
execute_writefile:
        push ebp
        mov ebp,esp
        pushad
        call reset_file_variables
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        test ecx,ecx
        jz .bad
        push ecx
        push esi
        call find_top_level_comma
        test eax,eax
        jz .bad
        mov ebx,eax
        mov edx,eax
        sub edx,esi
        push eval_temp
        push edx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .done
        mov esi,eval_temp
        mov edi,file_relative_path
        call copy_z_limited_path

        lea esi,[ebx+1]
        mov ecx,[ebp+8]
        add ecx,[ebp+12]
        sub ecx,esi
        push eval_buffer
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .done

        mov esi,file_relative_path
        call validate_relative_path_z
        test eax,eax
        jz .path_error
        mov esi,file_relative_path
        call is_writable_data_path_z
        test eax,eax
        jz .write_scope
        push file_full_path
        push file_relative_path
        call build_app_path_z
        test eax,eax
        jz .path_error

        mov eax,CREATE_ALWAYS
        cmp dword [ebp+16],0
        je .mode_ready
        mov eax,OPEN_ALWAYS
.mode_ready:
        push 0
        push FILE_ATTRIBUTE_NORMAL
        push eax
        push 0
        push FILE_SHARE_READ
        push GENERIC_WRITE
        push file_full_path
        call [CreateFileA]
        cmp eax,INVALID_HANDLE_VALUE
        je .open_error
        mov [file_handle],eax
        cmp dword [ebp+16],0
        je .write
        push FILE_END
        push 0
        push 0
        push eax
        call [SetFilePointer]
.write:
        mov esi,eval_buffer
        call strlen_esi
        mov [file_operation_size],eax
        xor edi,edi
.write_loop:
        mov eax,[file_operation_size]
        sub eax,edi
        jz .success
        push 0
        push bytes_done
        push eax
        lea edx,[eval_buffer+edi]
        push edx
        push dword [file_handle]
        call [WriteFile]
        test eax,eax
        jz .write_error
        mov eax,[bytes_done]
        test eax,eax
        jz .write_error
        add edi,eax
        jmp .write_loop
.success:
        push dword [file_handle]
        call [CloseHandle]
        mov dword [file_handle],INVALID_HANDLE_VALUE
        push text_one
        push var_file_ok
        call set_variable_z
        mov eax,[file_operation_size]
        mov edi,file_size_text
        call utoa_eax
        push file_size_text
        push var_file_size
        call set_variable_z
        push file_full_path
        push var_file_path
        call set_variable_z
        push text_empty
        push var_file_error
        call set_variable_z
        jmp .done
.bad:
        push file_err_syntax
        call set_file_error_z
        jmp .done
.path_error:
        push file_err_path
        call set_file_error_z
        jmp .done
.write_scope:
        push file_err_scope
        call set_file_error_z
        jmp .done
.open_error:
        push file_err_open
        call set_file_error_z
        jmp .done
.write_error:
        push file_err_write
        call set_file_error_z
        cmp dword [file_handle],INVALID_HANDLE_VALUE
        je .done
        push dword [file_handle]
        call [CloseHandle]
        mov dword [file_handle],INVALID_HANDLE_VALUE
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 12

; evaluate_readfile_function(inner_ptr,inner_len,destination,hex_mode)
evaluate_readfile_function:
        push ebp
        mov ebp,esp
        push esi
        push edi
        push ebx
        push ecx
        push edx
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .error
        mov esi,eval_temp
        call validate_relative_path_z
        test eax,eax
        jz .path_error
        push file_full_path
        push eval_temp
        call build_app_path_z
        test eax,eax
        jz .path_error
        push 0
        push FILE_ATTRIBUTE_NORMAL
        push OPEN_EXISTING
        push 0
        push FILE_SHARE_READ
        push GENERIC_READ
        push file_full_path
        call [CreateFileA]
        cmp eax,INVALID_HANDLE_VALUE
        je .open_error
        mov [file_handle],eax
        push file_size64
        push eax
        call [GetFileSizeEx]
        test eax,eax
        jz .size_error
        cmp dword [file_size64+4],0
        jne .large
        mov eax,dword [file_size64]
        cmp dword [ebp+20],0
        jne .hex_limit
        cmp eax,MAX_FILE_TEXT
        ja .large
        mov [file_operation_size],eax
        mov edi,[ebp+16]
        jmp .read
.hex_limit:
        cmp eax,MAX_FILE_BINARY
        ja .large
        mov [file_operation_size],eax
        mov edi,file_binary_buffer
.read:
        push 0
        push bytes_done
        push dword [file_operation_size]
        push edi
        push dword [file_handle]
        call [ReadFile]
        test eax,eax
        jz .read_error
        mov eax,[bytes_done]
        cmp eax,[file_operation_size]
        jne .read_error
        push dword [file_handle]
        call [CloseHandle]
        mov dword [file_handle],INVALID_HANDLE_VALUE
        cmp dword [ebp+20],0
        jne .encode_hex

        ; ApacheBAS strings are NUL-terminated. Direct text reads reject NUL;
        ; READHEX$ is the binary-safe representation.
        mov esi,[ebp+16]
        mov ecx,[file_operation_size]
.check_nul:
        test ecx,ecx
        jz .text_finish
        cmp byte [esi],0
        je .binary_in_text
        inc esi
        dec ecx
        jmp .check_nul
.text_finish:
        mov edi,[ebp+16]
        add edi,[file_operation_size]
        mov byte [edi],0
        mov eax,[file_operation_size]
        jmp .done
.encode_hex:
        mov esi,file_binary_buffer
        mov edi,[ebp+16]
        mov ecx,[file_operation_size]
.hex_loop:
        test ecx,ecx
        jz .hex_done
        movzx eax,byte [esi]
        mov edx,eax
        shr eax,4
        mov al,[digits_upper+eax]
        stosb
        and edx,15
        mov al,[digits_upper+edx]
        stosb
        inc esi
        dec ecx
        jmp .hex_loop
.hex_done:
        mov byte [edi],0
        mov eax,[file_operation_size]
        shl eax,1
        jmp .done
.path_error:
        push msg_readfile_path
        call set_runtime_error_z
        jmp .error
.open_error:
        push msg_readfile_open
        call set_runtime_error_z
        jmp .error
.size_error:
        push msg_readfile_size
        call set_runtime_error_z
        jmp .close_error
.large:
        push msg_readfile_large
        call set_runtime_error_z
        jmp .close_error
.read_error:
        push msg_readfile_read
        call set_runtime_error_z
        jmp .close_error
.binary_in_text:
        push msg_readfile_binary
        call set_runtime_error_z
.close_error:
        cmp dword [file_handle],INVALID_HANDLE_VALUE
        je .error
        push dword [file_handle]
        call [CloseHandle]
        mov dword [file_handle],INVALID_HANDLE_VALUE
.error:
        mov edi,[ebp+16]
        mov byte [edi],0
        xor eax,eax
.done:
        pop edx
        pop ecx
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 16

; copy zero-terminated path into PATH_SIZE buffer: ESI source, EDI destination.
copy_z_limited_path:
        push ecx
        mov ecx,PATH_SIZE-1
.loop:
        lodsb
        test al,al
        jz .finish
        stosb
        loop .loop
.finish:
        mov byte [edi],0
        pop ecx
        ret

; reset EXEC_* variables.
reset_exec_variables:
        push text_zero
        push var_exec_ok
        call set_variable_z
        push text_zero
        push var_exec_code
        call set_variable_z
        push text_empty
        push var_exec_output
        call set_variable_z
        push text_empty
        push var_exec_error
        call set_variable_z
        ret

set_exec_error_z:
        push ebp
        mov ebp,esp
        push text_zero
        push var_exec_ok
        call set_variable_z
        push dword [ebp+8]
        push var_exec_error
        call set_variable_z
        mov esp,ebp
        pop ebp
        ret 4

; Validate a relative executable path ending in .exe.
; Subdirectories are accepted. The path remains rooted beside the requested .bas
; file through build_app_path_z; absolute paths and traversal remain rejected.
validate_executable_path_z:
        push esi
        call validate_relative_path_z
        test eax,eax
        jz .no
        pop esi
        push esi
        call path_extension_z
        test eax,eax
        jz .no_pop
        mov esi,eax
        mov edi,ext_exe
        call strings_equal_z
        test eax,eax
        jz .no_pop
        mov eax,1
        pop esi
        ret
.no_pop:
        pop esi
        xor eax,eax
        ret
.no:
        pop esi
        xor eax,eax
        ret

; build_exec_paths(executable): creates the full executable path and the
; application working directory. A path containing a separator remains rooted
; below the .bas directory. A simple basename is searched first beside the
; .bas file and then through the normal Windows executable search path
; (System32, Windows and PATH), so system tools do not need to be copied.
build_exec_paths:
        push ebp
        mov ebp,esp
        pushad
        mov dword [exec_build_result],0

        ; Determine the working directory from SCRIPT_FILENAME/PATH_TRANSLATED.
        mov esi,script_path
        xor edx,edx
.find_script_sep:
        mov al,[esi]
        test al,al
        jz .script_ready
        cmp al,'\'
        je .remember_script_sep
        cmp al,'/'
        jne .next_script_char
.remember_script_sep:
        lea edx,[esi+1]
.next_script_char:
        inc esi
        jmp .find_script_sep
.script_ready:
        mov edi,exec_work_directory
        test edx,edx
        jz .current_directory
        mov ecx,edx
        sub ecx,script_path
        mov esi,script_path
        rep movsb
        mov byte [edi],0
        jmp .classify_name
.current_directory:
        mov byte [edi],'.'
        mov byte [edi+1],0

.classify_name:
        mov esi,[ebp+8]
.scan_name:
        mov al,[esi]
        test al,al
        jz .search_basename
        cmp al,'\'
        je .relative_path
        cmp al,'/'
        je .relative_path
        inc esi
        jmp .scan_name

.relative_path:
        push exec_full_path
        push dword [ebp+8]
        call build_app_path_z
        mov [exec_build_result],eax
        jmp .done

.search_basename:
        ; Prefer an executable placed beside the .bas file.
        push 0
        push exec_full_path
        push PATH_SIZE
        push 0
        push dword [ebp+8]
        push exec_work_directory
        call [SearchPathA]
        test eax,eax
        jz .search_windows
        cmp eax,PATH_SIZE
        jae .done
        mov dword [exec_build_result],1
        jmp .done

.search_windows:
        ; Fall back to the standard Windows search path, including System32.
        push 0
        push exec_full_path
        push PATH_SIZE
        push 0
        push dword [ebp+8]
        push 0
        call [SearchPathA]
        test eax,eax
        jz .done
        cmp eax,PATH_SIZE
        jae .done
        mov dword [exec_build_result],1
.done:
        popad
        mov eax,[exec_build_result]
        mov esp,ebp
        pop ebp
        ret 4

; Reset START_* variables.
reset_start_variables:
        push text_zero
        push var_start_ok
        call set_variable_z
        push text_empty
        push var_start_error
        call set_variable_z
        ret

set_start_error_z:
        push ebp
        mov ebp,esp
        push text_zero
        push var_start_ok
        call set_variable_z
        push dword [ebp+8]
        push var_start_error
        call set_variable_z
        mov esp,ebp
        pop ebp
        ret 4

; execute_start(pointer,length)
; Launches a Windows executable normally and returns immediately. It does not
; redirect output, wait for completion or terminate the child process.
execute_start:
        push ebp
        mov ebp,esp
        pushad
        call reset_start_variables
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        test ecx,ecx
        jz .bad
        push ecx
        push esi
        call find_top_level_comma
        mov ebx,eax
        test eax,eax
        jz .file_only
        mov edx,eax
        sub edx,esi
        push eval_temp
        push edx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .done
        mov esi,eval_temp
        mov edi,exec_tool_name
        call copy_z_limited_path
        lea esi,[ebx+1]
        mov ecx,[ebp+8]
        add ecx,[ebp+12]
        sub ecx,esi
        push eval_buffer
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .done
        jmp .file_ready
.file_only:
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .done
        mov esi,eval_temp
        mov edi,exec_tool_name
        call copy_z_limited_path
        mov byte [eval_buffer],0
.file_ready:
        mov esi,exec_tool_name
        call validate_executable_path_z
        test eax,eax
        jz .path_error
        push exec_tool_name
        call build_exec_paths
        test eax,eax
        jz .path_error

        ; Mutable command line: "full.exe" ["single argument"].
        mov edi,exec_command_line
        mov byte [edi],'"'
        inc edi
        mov ebx,exec_full_path
        call copy_z_advance_nozero
        mov byte [edi],'"'
        inc edi
        cmp byte [eval_buffer],0
        je .command_done
        mov byte [edi],' '
        inc edi
        mov byte [edi],'"'
        inc edi
        mov esi,eval_buffer
.arg_loop:
        mov al,[esi]
        test al,al
        jz .arg_done
        cmp al,'"'
        je .argument_error
        cmp al,13
        je .argument_error
        cmp al,10
        je .argument_error
        mov [edi],al
        inc edi
        inc esi
        cmp edi,exec_command_line+MAX_EXEC_COMMAND-3
        jae .argument_error
        jmp .arg_loop
.arg_done:
        mov byte [edi],'"'
        inc edi
.command_done:
        mov byte [edi],0

        mov edi,exec_startup_info
        mov ecx,68/4
        xor eax,eax
        rep stosd
        mov dword [exec_startup_info],68
        mov dword [exec_startup_info+44],STARTF_USESHOWWINDOW
        mov word [exec_startup_info+48],SW_SHOWNORMAL
        mov edi,exec_process_info
        mov ecx,16/4
        xor eax,eax
        rep stosd

        push exec_process_info
        push exec_startup_info
        push exec_work_directory
        push 0
        push 0
        push 0
        push 0
        push 0
        push exec_command_line
        push exec_full_path
        call [CreateProcessA]
        test eax,eax
        jz .launch_error

        push dword [exec_process_info+4]
        call [CloseHandle]
        push dword [exec_process_info]
        call [CloseHandle]
        push text_one
        push var_start_ok
        call set_variable_z
        push text_empty
        push var_start_error
        call set_variable_z
        jmp .done
.bad:
        push start_err_syntax
        call set_start_error_z
        jmp .done
.path_error:
        push start_err_path
        call set_start_error_z
        jmp .done
.argument_error:
        push start_err_argument
        call set_start_error_z
        jmp .done
.launch_error:
        push start_err_launch
        call set_start_error_z
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; execute_exec(pointer,length)
; A relative or PATH-resolved .exe is launched without a shell.
; stdout and stderr are redirected to a unique temporary file and captured after exit.
execute_exec:
        push ebp
        mov ebp,esp
        pushad
        call reset_exec_variables
        mov dword [exec_timed_out],0
        mov dword [exec_output_handle],INVALID_HANDLE_VALUE
        mov dword [exec_read_handle],INVALID_HANDLE_VALUE
        mov byte [exec_temp_file],0
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        test ecx,ecx
        jz .bad
        push ecx
        push esi
        call find_top_level_comma
        mov ebx,eax
        test eax,eax
        jz .tool_only
        mov edx,eax
        sub edx,esi
        push eval_temp
        push edx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .done
        mov esi,eval_temp
        mov edi,exec_tool_name
        call copy_z_limited_path
        lea esi,[ebx+1]
        mov ecx,[ebp+8]
        add ecx,[ebp+12]
        sub ecx,esi
        push eval_buffer
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .done
        jmp .tool_ready
.tool_only:
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .done
        mov esi,eval_temp
        mov edi,exec_tool_name
        call copy_z_limited_path
        mov byte [eval_buffer],0
.tool_ready:
        mov esi,exec_tool_name
        call validate_executable_path_z
        test eax,eax
        jz .path_error
        push exec_tool_name
        call build_exec_paths
        test eax,eax
        jz .path_error

        ; Build mutable command line: "full.exe" ["single argument"].
        mov edi,exec_command_line
        mov byte [edi],'"'
        inc edi
        mov ebx,exec_full_path
        call copy_z_advance_nozero
        mov byte [edi],'"'
        inc edi
        cmp byte [eval_buffer],0
        je .command_done
        mov byte [edi],' '
        inc edi
        mov byte [edi],'"'
        inc edi
        mov esi,eval_buffer
.arg_loop:
        mov al,[esi]
        test al,al
        jz .arg_done
        cmp al,'"'
        je .argument_error
        cmp al,13
        je .argument_error
        cmp al,10
        je .argument_error
        mov [edi],al
        inc edi
        inc esi
        cmp edi,exec_command_line+MAX_EXEC_COMMAND-3
        jae .argument_error
        jmp .arg_loop
.arg_done:
        mov byte [edi],'"'
        inc edi
.command_done:
        mov byte [edi],0

        push exec_temp_directory
        push PATH_SIZE
        call [GetTempPathA]
        test eax,eax
        jz .temp_error
        cmp eax,PATH_SIZE
        jae .temp_error
        push exec_temp_file
        push 0
        push exec_temp_prefix
        push exec_temp_directory
        call [GetTempFileNameA]
        test eax,eax
        jz .temp_error

        push 0
        push FILE_ATTRIBUTE_NORMAL
        push CREATE_ALWAYS
        push exec_security_attributes
        push FILE_SHARE_READ
        push GENERIC_WRITE
        push exec_temp_file
        call [CreateFileA]
        cmp eax,INVALID_HANDLE_VALUE
        je .temp_open_error
        mov [exec_output_handle],eax

        ; Clear STARTUPINFO/PROCESS_INFORMATION except cb and required handles.
        mov edi,exec_startup_info
        mov ecx,68/4
        xor eax,eax
        rep stosd
        mov dword [exec_startup_info],68
        mov dword [exec_startup_info+44],STARTF_USESHOWWINDOW or STARTF_USESTDHANDLES
        mov word [exec_startup_info+48],0
        push STD_INPUT_HANDLE
        call [GetStdHandle]
        mov dword [exec_startup_info+56],eax
        mov eax,[exec_output_handle]
        mov dword [exec_startup_info+60],eax
        mov dword [exec_startup_info+64],eax
        mov edi,exec_process_info
        mov ecx,16/4
        xor eax,eax
        rep stosd

        push exec_process_info
        push exec_startup_info
        push exec_work_directory
        push 0
        push CREATE_NO_WINDOW
        push 1
        push 0
        push 0
        push exec_command_line
        push exec_full_path
        call [CreateProcessA]
        test eax,eax
        jz .process_error

        push dword [exec_output_handle]
        call [CloseHandle]
        mov dword [exec_output_handle],INVALID_HANDLE_VALUE
        push EXEC_TIMEOUT_MS
        push dword [exec_process_info]
        call [WaitForSingleObject]
        cmp eax,WAIT_TIMEOUT
        jne .finished
        mov dword [exec_timed_out],1
        push 124
        push dword [exec_process_info]
        call [TerminateProcess]
        push 1000
        push dword [exec_process_info]
        call [WaitForSingleObject]
.finished:
        push exec_exit_code
        push dword [exec_process_info]
        call [GetExitCodeProcess]
        push dword [exec_process_info+4]
        call [CloseHandle]
        push dword [exec_process_info]
        call [CloseHandle]

        ; Read captured text into the dedicated 1 MiB EXEC_OUTPUT$ buffer.
        ; Keep reading because ReadFile may legally return fewer bytes than asked.
        push 0
        push FILE_ATTRIBUTE_NORMAL
        push OPEN_EXISTING
        push 0
        push FILE_SHARE_READ
        push GENERIC_READ
        push exec_temp_file
        call [CreateFileA]
        cmp eax,INVALID_HANDLE_VALUE
        je .capture_error
        mov [exec_read_handle],eax
        mov dword [exec_output_length],0
        mov dword [exec_output_truncated],0
.capture_read_more:
        mov eax,EXEC_OUTPUT_SIZE-1
        sub eax,[exec_output_length]
        jz .capture_probe_extra
        push 0
        push bytes_done
        push eax
        mov edx,exec_output_buffer
        add edx,[exec_output_length]
        push edx
        push dword [exec_read_handle]
        call [ReadFile]
        test eax,eax
        jz .capture_read_error
        mov eax,[bytes_done]
        test eax,eax
        jz .capture_read_complete
        add [exec_output_length],eax
        jmp .capture_read_more

.capture_probe_extra:
        ; When the buffer is full, read one byte to distinguish an exact-size
        ; result from a genuinely truncated result.
        push 0
        push bytes_done
        push 1
        push exec_output_probe
        push dword [exec_read_handle]
        call [ReadFile]
        test eax,eax
        jz .capture_read_error
        cmp dword [bytes_done],0
        je .capture_read_complete
        mov dword [exec_output_truncated],1

.capture_read_complete:
        mov eax,[exec_output_length]
        mov byte [exec_output_buffer+eax],0
        push dword [exec_read_handle]
        call [CloseHandle]
        mov dword [exec_read_handle],INVALID_HANDLE_VALUE
        push exec_temp_file
        call [DeleteFileA]

        cmp dword [exec_timed_out],0
        jne .timeout_result
        push text_one
        push var_exec_ok
        call set_variable_z
        mov eax,[exec_exit_code]
        mov edi,exec_code_text
        call utoa_eax
        push exec_code_text
        push var_exec_code
        call set_variable_z
        ; EXEC_OUTPUT$ already points at exec_output_buffer.
        push text_empty
        push var_exec_error
        call set_variable_z
        jmp .done
.timeout_result:
        mov eax,124
        mov edi,exec_code_text
        call utoa_eax
        push exec_code_text
        push var_exec_code
        call set_variable_z
        push exec_err_timeout
        call set_exec_error_z
        jmp .done
.bad:
        push exec_err_syntax
        call set_exec_error_z
        jmp .done
.path_error:
        push exec_err_tool
        call set_exec_error_z
        jmp .done
.argument_error:
        push exec_err_argument
        call set_exec_error_z
        jmp .cleanup_temp
.temp_error:
        push exec_err_temp
        call set_exec_error_z
        jmp .done
.temp_open_error:
        push exec_err_temp_open
        call set_exec_error_z
        jmp .cleanup_temp
.process_error:
        push exec_err_launch
        call set_exec_error_z
        jmp .cleanup_handles
.capture_error:
        push exec_err_capture
        call set_exec_error_z
        jmp .cleanup_temp
.capture_read_error:
        mov eax,[exec_output_length]
        cmp eax,EXEC_OUTPUT_SIZE-1
        jbe .capture_error_length_ok
        mov eax,EXEC_OUTPUT_SIZE-1
.capture_error_length_ok:
        mov byte [exec_output_buffer+eax],0
        push exec_err_capture_read
        call set_exec_error_z
.cleanup_handles:
        cmp dword [exec_output_handle],INVALID_HANDLE_VALUE
        je .cleanup_read
        push dword [exec_output_handle]
        call [CloseHandle]
        mov dword [exec_output_handle],INVALID_HANDLE_VALUE
.cleanup_read:
        cmp dword [exec_read_handle],INVALID_HANDLE_VALUE
        je .cleanup_temp
        push dword [exec_read_handle]
        call [CloseHandle]
        mov dword [exec_read_handle],INVALID_HANDLE_VALUE
.cleanup_temp:
        cmp byte [exec_temp_file],0
        je .done
        push exec_temp_file
        call [DeleteFileA]
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; execute_print(pointer,length)
execute_print:
        push ebp
        mov ebp,esp
        pushad
        mov esi,[ebp+8]
        mov edi,esi
        add edi,[ebp+12]

        ; Compatibility with the VB6 ApacheBAS web bridge. A PRINT whose
        ; entire expression is a literal beginning with @@ configures the CGI
        ; response instead of adding text to the body.
        push dword [ebp+12]
        push dword [ebp+8]
        call try_print_directive
        test eax,eax
        jnz .done

        mov [print_had_item],0
        mov [print_trailing_semicolon],0

        cmp esi,edi
        jne .item_start
        push crlf_len
        push crlf
        call output_append_span
        jmp .done

.item_start:
        mov ebx,esi
        xor edx,edx                     ; quote state
        xor ecx,ecx                     ; parenthesis depth
.scan:
        cmp esi,edi
        jae .last_item
        mov al,[esi]
        cmp al,'"'
        jne .not_quote
        xor edx,1
        inc esi
        jmp .scan
.not_quote:
        test edx,edx
        jnz .advance
        cmp al,'('
        jne .not_open
        inc ecx
        jmp .advance
.not_open:
        cmp al,')'
        jne .separator
        test ecx,ecx
        jz .advance
        dec ecx
        jmp .advance
.separator:
        test ecx,ecx
        jnz .advance
        cmp al,';'
        je .emit_item
        cmp al,','
        je .emit_comma_item
.advance:
        inc esi
        jmp .scan

.emit_comma_item:
        push 1
        jmp .emit_common
.emit_item:
        push 0
.emit_common:
        mov eax,esi
        sub eax,ebx
        push eval_buffer
        push eax
        push ebx
        call evaluate_atom
        push eax
        push eval_buffer
        call output_append_span
        mov [print_had_item],1
        pop eax                         ; comma flag
        test eax,eax
        jz .after_separator
        push 1
        push one_space
        call output_append_span
.after_separator:
        inc esi
        mov ebx,esi
        cmp esi,edi
        jne .scan
        mov [print_trailing_semicolon],1
        jmp .finish

.last_item:
        mov eax,esi
        sub eax,ebx
        push eval_buffer
        push eax
        push ebx
        call evaluate_atom
        push eax
        push eval_buffer
        call output_append_span
        mov [print_had_item],1
.finish:
        cmp [print_trailing_semicolon],0
        jne .done
        push crlf_len
        push crlf
        call output_append_span
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; execute_if(pointer,length) -- one-line IF condition THEN statement
execute_if:
        push ebp
        mov ebp,esp
        pushad
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        push keyword_then
        push ecx
        push esi
        call find_keyword_outside
        test eax,eax
        jz .bad
        mov ebx,eax                     ; pointer to THEN
        mov edx,eax
        sub edx,esi
        push edx
        push esi
        call evaluate_condition
        mov [if_condition_result],eax

        ; Tail after THEN. Detect an optional ELSE outside strings.
        mov esi,ebx
        add esi,4
        mov ecx,[ebp+8]
        add ecx,[ebp+12]
        sub ecx,esi
        call trim_span
        mov [if_then_ptr],esi
        mov [if_then_len],ecx
        push keyword_else
        push ecx
        push esi
        call find_keyword_outside
        mov [if_else_ptr],eax

        cmp [if_condition_result],0
        je .false_branch

        ; True: execute text between THEN and ELSE, or the whole tail.
        mov esi,[if_then_ptr]
        mov ecx,[if_then_len]
        mov eax,[if_else_ptr]
        test eax,eax
        jz .run_selected
        mov ecx,eax
        sub ecx,esi
        jmp .run_selected

.false_branch:
        mov esi,[if_else_ptr]
        test esi,esi
        jz .done
        add esi,4
        mov ecx,[ebp+8]
        add ecx,[ebp+12]
        sub ecx,esi

.run_selected:
        call trim_span
        test ecx,ecx
        jz .done
        push ecx
        push esi
        call execute_statement
        jmp .done
.bad:
        push msg_bad_if
        call set_runtime_error_z
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; evaluate_condition(pointer,length), returns EAX boolean.
; Conditions are ordinary expressions. Comparisons return BASIC TRUE (-1) or 0.
evaluate_condition:
        push ebp
        mov ebp,esp
        push esi
        push eval_buffer
        push dword [ebp+12]
        push dword [ebp+8]
        call evaluate_atom
        mov esi,eval_buffer
        call truthy_z
        pop esi
        mov esp,ebp
        pop ebp
        ret 8

; evaluate_atom(pointer,length,destination): recursive expression evaluator with v0.1.31 decimal arithmetic.
evaluate_atom:
        push ebp
        mov ebp,esp
        pushad
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        mov edi,[ebp+16]
        mov dword [expr_return_length],0
        call trim_span
        call strip_outer_parentheses
        ; find_lowest_operator is a register-based helper (ESI/ECX input).
        ; Do not push pseudo-arguments here: it returns with RET, not RET 8.
        ; The two stale stack values in v0.1.4 displaced POPAD and destroyed
        ; EBP before the function epilogue, causing a native CGI crash.
        call find_lowest_operator
        test eax,eax
        jz .unary
        ; Save current expression and operator on the CPU stack because
        ; recursive evaluations may freely reuse the scanner globals.
        mov edi,esi
        add edi,ecx
        push edi                         ; [esp+24] expression end
        push esi                         ; [esp+20] expression start
        push ebx                         ; [esp+16] operator length
        push edx                         ; [esp+12] operator kind
        push eax                         ; [esp+8]  operator pointer
        call alloc_eval_slot
        push eax                         ; [esp+4]  left buffer
        call alloc_eval_slot
        push eax                         ; [esp]    right buffer

        mov edx,[esp+8]
        sub edx,[esp+20]
        push dword [esp+4]               ; left buffer (offset changed after push)
        push edx
        push dword [esp+28]              ; expression start (offset changed)
        call evaluate_atom

        mov eax,[esp+8]
        add eax,[esp+16]
        mov edx,[esp+24]
        sub edx,eax
        push dword [esp]                 ; right buffer
        push edx
        push eax
        call evaluate_atom

        mov edx,[esp+12]                 ; kind
        mov eax,[esp+4]                  ; left buffer
        mov ecx,[esp]                    ; right buffer
        push dword [ebp+16]
        push ecx
        push eax
        push edx
        call apply_binary_operator
        add esp,28
        sub dword [eval_work_depth],2
        jmp .length
.unary:
        call trim_span
        push token_true
        push ecx
        push esi
        call equals_keyword_span
        test eax,eax
        jnz .constant_true
        push token_false
        push ecx
        push esi
        call equals_keyword_span
        test eax,eax
        jnz .constant_false
        push keyword_not
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jnz .unary_not
        cmp byte [esi],'-'
        je .unary_minus
        cmp byte [esi],'+'
        je .unary_plus
        push dword [ebp+16]
        push ecx
        push esi
        call evaluate_primary_v013
        mov [expr_return_length],eax
        jmp .done
.constant_true:
        mov edi,[ebp+16]
        mov byte [edi],'-'
        mov byte [edi+1],'1'
        mov byte [edi+2],0
        mov dword [expr_return_length],2
        jmp .done
.constant_false:
        mov edi,[ebp+16]
        mov byte [edi],'0'
        mov byte [edi+1],0
        mov dword [expr_return_length],1
        jmp .done
.unary_not:
        add esi,eax
        sub ecx,eax
        call trim_span
        call alloc_eval_slot
        mov ebx,eax
        push ebx
        push ecx
        push esi
        call evaluate_atom
        mov esi,ebx
        call atoi_signed
        not eax
        mov edi,[ebp+16]
        call itoa_eax
        dec dword [eval_work_depth]
        jmp .length
.unary_minus:
        inc esi
        dec ecx
        call trim_span
        call alloc_eval_slot
        mov ebx,eax
        push ebx
        push ecx
        push esi
        call evaluate_atom
        mov esi,ebx
        call contains_decimal_z
        test eax,eax
        jz .unary_minus_integer
        mov esi,ebx
        call parse_decimal_to_fpu
        test eax,eax
        jz .unary_minus_error
        fchs
        mov edi,[ebp+16]
        call format_fpu_decimal6
        jmp .unary_minus_finish
.unary_minus_integer:
        mov esi,ebx
        call atoi_signed
        neg eax
        mov edi,[ebp+16]
        call itoa_eax
        jmp .unary_minus_finish
.unary_minus_error:
        push msg_bad_real_argument
        call set_runtime_error_z
        mov edi,[ebp+16]
        mov byte [edi],0
.unary_minus_finish:
        dec dword [eval_work_depth]
        jmp .length
.unary_plus:
        inc esi
        dec ecx
        call trim_span
        push dword [ebp+16]
        push ecx
        push esi
        call evaluate_atom
        jmp .done
.length:
        mov esi,[ebp+16]
        call strlen_esi
        mov [expr_return_length],eax
.done:
        popad
        mov eax,[expr_return_length]
        mov esp,ebp
        pop ebp
        ret 12

strip_outer_parentheses:
.again:
        call trim_span
        cmp ecx,2
        jb .done
        cmp byte [esi],'('
        jne .done
        cmp byte [esi+ecx-1],')'
        jne .done
        push esi
        push ecx
        mov edi,esi
        add edi,ecx
        mov ebx,1
        xor edx,edx
        inc esi
.scan:
        cmp esi,edi
        jae .not_wrapped
        mov al,[esi]
        cmp al,'"'
        jne .not_quote
        xor edx,1
        inc esi
        jmp .scan
.not_quote:
        test edx,edx
        jnz .advance
        cmp al,'('
        jne .close
        inc ebx
        jmp .advance
.close:
        cmp al,')'
        jne .advance
        dec ebx
        jnz .advance
        lea eax,[esi+1]
        cmp eax,edi
        jne .not_wrapped
        pop ecx
        pop esi
        inc esi
        sub ecx,2
        jmp .again
.advance:
        inc esi
        jmp .scan
.not_wrapped:
        pop ecx
        pop esi
.done:
        ret


; Finds the lowest-precedence top-level operator.
; Input ESI/ECX. Output EAX pointer or 0, EDX kind, EBX length.
find_lowest_operator:
        push esi
        push edi
        push ecx
        mov dword [scan_best_ptr],0
        mov dword [scan_best_prec],100
        mov dword [scan_depth],0
        mov dword [scan_quote],0
        mov [scan_start],esi
        lea edi,[esi+ecx]
.scan:
        cmp esi,edi
        jae .finish
        mov al,[esi]
        cmp al,'"'
        jne .not_quote
        cmp dword [scan_quote],0
        je .toggle_quote
        lea eax,[esi+1]
        cmp eax,edi
        jae .toggle_quote
        cmp byte [esi+1],'"'
        jne .toggle_quote
        add esi,2
        jmp .scan
.toggle_quote:
        xor dword [scan_quote],1
        inc esi
        jmp .scan
.not_quote:
        cmp dword [scan_quote],0
        jne .advance
        cmp al,'('
        jne .not_open
        inc dword [scan_depth]
        jmp .advance
.not_open:
        cmp al,')'
        jne .at_depth
        cmp dword [scan_depth],0
        jle .advance
        dec dword [scan_depth]
        jmp .advance
.at_depth:
        cmp dword [scan_depth],0
        jne .advance

        ; Word operators.
        push edi
        push esi
        push op_word_or
        call match_word_from_ptr
        test eax,eax
        jnz .word_or
        push edi
        push esi
        push op_word_xor
        call match_word_from_ptr
        test eax,eax
        jnz .word_xor
        push edi
        push esi
        push op_word_and
        call match_word_from_ptr
        test eax,eax
        jnz .word_and
        push edi
        push esi
        push op_word_mod
        call match_word_from_ptr
        test eax,eax
        jnz .word_mod

        mov al,[esi]
        cmp al,'='
        je .char_eq
        cmp al,'<'
        je .char_lt
        cmp al,'>'
        je .char_gt
        cmp al,'&'
        je .char_concat
        cmp al,'+'
        je .char_add
        cmp al,'-'
        je .char_sub
        cmp al,'*'
        je .char_mul
        cmp al,'/'
        je .char_div
        cmp al,'\'
        je .char_idiv
        cmp al,'^'
        je .char_pow
        jmp .advance
.word_or:
        mov edx,OP_OR
        mov ebx,2
        mov ecx,1
        jmp .candidate
.word_xor:
        mov edx,OP_XOR
        mov ebx,3
        mov ecx,2
        jmp .candidate
.word_and:
        mov edx,OP_AND
        mov ebx,3
        mov ecx,3
        jmp .candidate
.word_mod:
        mov edx,OP_MOD
        mov ebx,3
        mov ecx,7
        jmp .candidate
.char_eq:
        mov edx,OP_EQ
        mov ebx,1
        mov ecx,4
        jmp .candidate
.char_lt:
        lea eax,[esi+1]
        cmp eax,edi
        jae .lt_one
        cmp byte [esi+1],'>'
        je .ne_two
        cmp byte [esi+1],'='
        je .le_two
.lt_one:
        mov edx,OP_LT
        mov ebx,1
        mov ecx,4
        jmp .candidate
.ne_two:
        mov edx,OP_NE
        mov ebx,2
        mov ecx,4
        jmp .candidate
.le_two:
        mov edx,OP_LE
        mov ebx,2
        mov ecx,4
        jmp .candidate
.char_gt:
        lea eax,[esi+1]
        cmp eax,edi
        jae .gt_one
        cmp byte [esi+1],'='
        je .ge_two
.gt_one:
        mov edx,OP_GT
        mov ebx,1
        mov ecx,4
        jmp .candidate
.ge_two:
        mov edx,OP_GE
        mov ebx,2
        mov ecx,4
        jmp .candidate
.char_concat:
        ; &H, &O and &B at token start are numeric literals, not concatenation.
        lea eax,[esi+1]
        cmp eax,edi
        jae .concat_yes
        mov al,[esi+1]
        or al,20h
        cmp al,'h'
        je .advance
        cmp al,'o'
        je .advance
        cmp al,'b'
        je .advance
.concat_yes:
        mov edx,OP_CONCAT
        mov ebx,1
        mov ecx,5
        jmp .candidate
.char_add:
        call operator_is_unary_here
        test eax,eax
        jnz .advance
        mov edx,OP_ADD
        mov ebx,1
        mov ecx,6
        jmp .candidate
.char_sub:
        call operator_is_unary_here
        test eax,eax
        jnz .advance
        mov edx,OP_SUB
        mov ebx,1
        mov ecx,6
        jmp .candidate
.char_mul:
        mov edx,OP_MUL
        mov ebx,1
        mov ecx,7
        jmp .candidate
.char_div:
        mov edx,OP_DIV
        mov ebx,1
        mov ecx,7
        jmp .candidate
.char_idiv:
        mov edx,OP_IDIV
        mov ebx,1
        mov ecx,7
        jmp .candidate
.char_pow:
        mov edx,OP_POW
        mov ebx,1
        mov ecx,8
.candidate:
        cmp ecx,[scan_best_prec]
        ja .advance_by_len
        jb .record
        cmp edx,OP_POW
        je .advance_by_len
.record:
        mov [scan_best_prec],ecx
        mov [scan_best_ptr],esi
        mov [scan_best_kind],edx
        mov [scan_best_len],ebx
.advance_by_len:
        add esi,ebx
        jmp .scan
.advance:
        inc esi
        jmp .scan
.finish:
        mov eax,[scan_best_ptr]
        mov edx,[scan_best_kind]
        mov ebx,[scan_best_len]
        pop ecx
        pop edi
        pop esi
        ret

; match_word_from_ptr(word_z,pointer,end_pointer) -> EAX bool
match_word_from_ptr:
        push ebp
        mov ebp,esp
        push esi
        push edi
        push ebx
        mov ebx,[ebp+8]
        mov esi,[ebp+12]
        mov edi,[ebp+16]
        ; left boundary
        cmp esi,[scan_start]
        je .left_ok
        mov al,[esi-1]
        call is_word_char_al
        test eax,eax
        jnz .no
.left_ok:
        xor ecx,ecx
.loop:
        mov al,[ebx+ecx]
        test al,al
        jz .right
        lea edx,[esi+ecx]
        cmp edx,edi
        jae .no
        mov ah,[esi+ecx]
        call compare_chars_i
        jne .no
        inc ecx
        jmp .loop
.right:
        lea edx,[esi+ecx]
        cmp edx,edi
        jae .yes
        mov al,[edx]
        call is_word_char_al
        test eax,eax
        jnz .no
.yes:
        mov eax,1
        jmp .done
.no:
        xor eax,eax
.done:
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 12

is_word_char_al:
        cmp al,'0'
        jb .letter
        cmp al,'9'
        jbe .yes
.letter:
        or al,20h
        cmp al,'a'
        jb .under
        cmp al,'z'
        jbe .yes
.under:
        cmp al,'_'
        je .yes
        cmp al,'$'
        je .yes
        xor eax,eax
        ret
.yes:
        mov eax,1
        ret

operator_is_unary_here:
        push esi
        mov eax,esi
        cmp eax,[scan_start]
        je .yes
.back:
        dec eax
        cmp eax,[scan_start]
        jb .yes
        mov dl,[eax]
        cmp dl,' '
        je .back
        cmp dl,9
        je .back
        cmp dl,'('
        je .yes
        cmp dl,'+'
        je .yes
        cmp dl,'-'
        je .yes
        cmp dl,'*'
        je .yes
        cmp dl,'/'
        je .yes
        cmp dl,'\'
        je .yes
        cmp dl,'^'
        je .yes
        cmp dl,'='
        je .yes
        cmp dl,'<'
        je .yes
        cmp dl,'>'
        je .yes
        cmp dl,'&'
        je .yes
        xor eax,eax
        pop esi
        ret
.yes:
        mov eax,1
        pop esi
        ret

alloc_eval_slot:
        mov eax,[eval_work_depth]
        cmp eax,EVAL_WORK_SLOTS
        jb .ok
        mov eax,EVAL_WORK_SLOTS-1
        jmp .ptr
.ok:
        inc dword [eval_work_depth]
.ptr:
        imul eax,EVAL_WORK_SIZE
        add eax,eval_work_buffers
        ret

; apply_binary_operator(kind,left_z,right_z,destination)
apply_binary_operator:
        push ebp
        mov ebp,esp
        pushad
        mov eax,[ebp+8]
        mov esi,[ebp+12]
        mov edi,[ebp+16]
        mov ebx,[ebp+20]
        cmp eax,OP_CONCAT
        je .concat
        cmp eax,OP_EQ
        je .comparison_type
        cmp eax,OP_NE
        je .comparison_type
        cmp eax,OP_ADD
        jne .numeric_select
        ; BASIC '+' concatenates when either operand is non-numeric.
        push edi
        call is_numeric_z
        mov edx,eax
        mov esi,[ebp+12]
        push esi
        call is_numeric_z
        and eax,edx
        test eax,eax
        jz .concat
        jmp .numeric_select
.comparison_type:
        ; Equality and inequality compare text when either operand is not a
        ; canonical signed decimal value.
        push dword [ebp+12]
        call is_numeric_z
        mov edx,eax
        push dword [ebp+16]
        call is_numeric_z
        and eax,edx
        test eax,eax
        jnz .numeric_select
        mov esi,[ebp+12]
        mov edi,[ebp+16]
        call strings_equal_z
        cmp dword [ebp+8],OP_EQ
        je .string_bool
        xor eax,1
.string_bool:
        neg eax
        mov edi,[ebp+20]
        call itoa_eax
        jmp .done

.numeric_select:
        mov eax,[ebp+8]
        ; Bitwise and explicitly integral operators retain the proven 32-bit
        ; path even when their operands originated as decimal text.
        cmp eax,OP_OR
        je .integer_numeric
        cmp eax,OP_XOR
        je .integer_numeric
        cmp eax,OP_AND
        je .integer_numeric
        cmp eax,OP_IDIV
        je .integer_numeric
        cmp eax,OP_MOD
        je .integer_numeric
        cmp eax,OP_POW
        je .integer_numeric
        ; '/' is always real division. The remaining arithmetic/comparison
        ; operators use x87 when either operand contains a decimal point.
        cmp eax,OP_DIV
        je .real_numeric
        mov esi,[ebp+12]
        call contains_decimal_z
        test eax,eax
        jnz .real_numeric
        mov esi,[ebp+16]
        call contains_decimal_z
        test eax,eax
        jnz .real_numeric

.integer_numeric:
        mov esi,[ebp+12]
        call atoi_signed
        mov [binary_left_num],eax
        mov esi,[ebp+16]
        call atoi_signed
        mov [binary_right_num],eax
        mov eax,[ebp+8]
        cmp eax,OP_OR
        je .op_or
        cmp eax,OP_XOR
        je .op_xor
        cmp eax,OP_AND
        je .op_and
        cmp eax,OP_EQ
        je .op_eq
        cmp eax,OP_NE
        je .op_ne
        cmp eax,OP_LT
        je .op_lt
        cmp eax,OP_LE
        je .op_le
        cmp eax,OP_GT
        je .op_gt
        cmp eax,OP_GE
        je .op_ge
        cmp eax,OP_ADD
        je .op_add
        cmp eax,OP_SUB
        je .op_sub
        cmp eax,OP_MUL
        je .op_mul
        cmp eax,OP_DIV
        je .op_div
        cmp eax,OP_IDIV
        je .op_div
        cmp eax,OP_MOD
        je .op_mod
        cmp eax,OP_POW
        je .op_pow
        xor eax,eax
        jmp .write_num
.op_or:
        mov eax,[binary_left_num]
        or eax,[binary_right_num]
        jmp .write_num
.op_xor:
        mov eax,[binary_left_num]
        xor eax,[binary_right_num]
        jmp .write_num
.op_and:
        mov eax,[binary_left_num]
        and eax,[binary_right_num]
        jmp .write_num
.op_eq:
        mov eax,[binary_left_num]
        cmp eax,[binary_right_num]
        sete al
        movzx eax,al
        neg eax
        jmp .write_num
.op_ne:
        mov eax,[binary_left_num]
        cmp eax,[binary_right_num]
        setne al
        movzx eax,al
        neg eax
        jmp .write_num
.op_lt:
        mov eax,[binary_left_num]
        cmp eax,[binary_right_num]
        setl al
        movzx eax,al
        neg eax
        jmp .write_num
.op_le:
        mov eax,[binary_left_num]
        cmp eax,[binary_right_num]
        setle al
        movzx eax,al
        neg eax
        jmp .write_num
.op_gt:
        mov eax,[binary_left_num]
        cmp eax,[binary_right_num]
        setg al
        movzx eax,al
        neg eax
        jmp .write_num
.op_ge:
        mov eax,[binary_left_num]
        cmp eax,[binary_right_num]
        setge al
        movzx eax,al
        neg eax
        jmp .write_num
.op_add:
        mov eax,[binary_left_num]
        add eax,[binary_right_num]
        jmp .write_num
.op_sub:
        mov eax,[binary_left_num]
        sub eax,[binary_right_num]
        jmp .write_num
.op_mul:
        mov eax,[binary_left_num]
        imul eax,[binary_right_num]
        jmp .write_num
.op_div:
        cmp dword [binary_right_num],0
        je .div_zero
        mov eax,[binary_left_num]
        cdq
        idiv dword [binary_right_num]
        jmp .write_num
.op_mod:
        cmp dword [binary_right_num],0
        je .div_zero
        mov eax,[binary_left_num]
        cdq
        idiv dword [binary_right_num]
        mov eax,edx
        jmp .write_num
.op_pow:
        mov ecx,[binary_right_num]
        test ecx,ecx
        js .zero_result
        mov eax,1
        mov edx,[binary_left_num]
.pow_loop:
        test ecx,ecx
        jz .write_num
        test ecx,1
        jz .pow_square
        imul eax,edx
.pow_square:
        imul edx,edx
        shr ecx,1
        jmp .pow_loop
.zero_result:
        xor eax,eax
.write_num:
        mov edi,[ebp+20]
        call itoa_eax
        jmp .done

.real_numeric:
        ; Validate and convert both operands to signed micro-units. The parser
        ; leaves ST0 populated, so discard it before parsing the second value.
        push dword [ebp+12]
        call is_numeric_z
        test eax,eax
        jz .real_bad
        push dword [ebp+16]
        call is_numeric_z
        test eax,eax
        jz .real_bad
        mov esi,[ebp+12]
        call parse_decimal_to_fpu
        test eax,eax
        jz .real_bad
        fstp st0
        mov eax,[fpu_scaled_input]
        mov [binary_left_scaled],eax
        mov esi,[ebp+16]
        call parse_decimal_to_fpu
        test eax,eax
        jz .real_bad
        fstp st0
        mov eax,[fpu_scaled_input]
        mov [binary_right_scaled],eax

        mov eax,[ebp+8]
        cmp eax,OP_EQ
        je .real_eq
        cmp eax,OP_NE
        je .real_ne
        cmp eax,OP_LT
        je .real_lt
        cmp eax,OP_LE
        je .real_le
        cmp eax,OP_GT
        je .real_gt
        cmp eax,OP_GE
        je .real_ge
        cmp eax,OP_DIV
        jne .real_load
        cmp dword [binary_right_scaled],0
        je .div_zero
.real_load:
        ; ST0=left, then ST0=right/ST1=left.
        fild dword [binary_left_scaled]
        fild dword [const_million]
        fdivp st1,st0
        fild dword [binary_right_scaled]
        fild dword [const_million]
        fdivp st1,st0
        mov eax,[ebp+8]
        cmp eax,OP_ADD
        je .real_add
        cmp eax,OP_SUB
        je .real_sub
        cmp eax,OP_MUL
        je .real_mul
        cmp eax,OP_DIV
        je .real_div
        finit
        jmp .real_bad
.real_add:
        faddp st1,st0
        jmp .real_write
.real_sub:
        fsubp st1,st0
        jmp .real_write
.real_mul:
        fmulp st1,st0
        jmp .real_write
.real_div:
        fdivp st1,st0
.real_write:
        mov edi,[ebp+20]
        call format_fpu_decimal6
        jmp .done
.real_eq:
        mov eax,[binary_left_scaled]
        cmp eax,[binary_right_scaled]
        sete al
        jmp .real_bool
.real_ne:
        mov eax,[binary_left_scaled]
        cmp eax,[binary_right_scaled]
        setne al
        jmp .real_bool
.real_lt:
        mov eax,[binary_left_scaled]
        cmp eax,[binary_right_scaled]
        setl al
        jmp .real_bool
.real_le:
        mov eax,[binary_left_scaled]
        cmp eax,[binary_right_scaled]
        setle al
        jmp .real_bool
.real_gt:
        mov eax,[binary_left_scaled]
        cmp eax,[binary_right_scaled]
        setg al
        jmp .real_bool
.real_ge:
        mov eax,[binary_left_scaled]
        cmp eax,[binary_right_scaled]
        setge al
.real_bool:
        movzx eax,al
        neg eax
        mov edi,[ebp+20]
        call itoa_eax
        jmp .done
.real_bad:
        finit
        push msg_bad_real_arithmetic
        call set_runtime_error_z
        mov edi,[ebp+20]
        mov byte [edi],0
        jmp .done

.concat:
        mov edi,[ebp+20]
        mov ebx,[ebp+12]
        call copy_z_advance_nozero
        mov ebx,[ebp+16]
        call copy_z_advance_nozero
        mov byte [edi],0
        jmp .done
.div_zero:
        finit
        push msg_division_zero
        call set_runtime_error_z
        mov edi,[ebp+20]
        mov byte [edi],0
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 16

; six_decimal_digits
; Input: EAX=0..999999, EDI=destination. Writes exactly six digits and
; advances EDI to the byte after them.
six_decimal_digits:
        push ebx
        push ecx
        push edx
        push esi
        mov ebx,100000
        mov ecx,6
.digit_loop:
        xor edx,edx
        div ebx
        add al,'0'
        stosb
        mov eax,edx
        push eax
        mov eax,ebx
        xor edx,edx
        mov esi,10
        div esi
        mov ebx,eax
        pop eax
        loop .digit_loop
        pop esi
        pop edx
        pop ecx
        pop ebx
        ret

; parse_sleep_milliseconds
; Input: ESI -> zero-terminated non-negative seconds. Accepts up to three
; fractional digits (for example 0.01 -> 10 ms). Returns EAX milliseconds.
parse_sleep_milliseconds:
        push ebx
        push ecx
        push edx
        push edi
        mov dword [sleep_fraction],0
        xor ebx,ebx                    ; whole seconds
        xor edi,edi                    ; at least one digit seen
.skip_space:
        mov al,[esi]
        cmp al,' '
        je .skip_one
        cmp al,9
        jne .sign
.skip_one:
        inc esi
        jmp .skip_space
.sign:
        cmp byte [esi],'-'
        je .bad
        cmp byte [esi],'+'
        jne .whole
        inc esi
.whole:
        mov al,[esi]
        cmp al,'0'
        jb .fraction
        cmp al,'9'
        ja .fraction
        imul ebx,10
        movzx eax,al
        sub eax,'0'
        add ebx,eax
        mov edi,1
        inc esi
        jmp .whole
.fraction:
        cmp byte [esi],'.'
        jne .finish
        inc esi
        mov ecx,100
.frac_loop:
        mov al,[esi]
        cmp al,'0'
        jb .finish
        cmp al,'9'
        ja .finish
        test ecx,ecx
        jz .skip_extra_fraction
        movzx eax,al
        sub eax,'0'
        imul eax,ecx
        add [sleep_fraction],eax
        mov eax,ecx
        xor edx,edx
        mov ecx,10
        div ecx
        mov ecx,eax
        mov edi,1
        inc esi
        jmp .frac_loop
.skip_extra_fraction:
        inc esi
        jmp .frac_loop
.finish:
        cmp edi,0
        je .bad
.trailing:
        mov al,[esi]
        test al,al
        jz .write
        cmp al,' '
        je .trail_one
        cmp al,9
        jne .bad
.trail_one:
        inc esi
        jmp .trailing
.write:
        mov eax,ebx
        imul eax,1000
        add eax,[sleep_fraction]
        mov dword [sleep_fraction],0
        jmp .done
.bad:
        mov dword [sleep_fraction],0
        push msg_bad_sleep
        call set_runtime_error_z
        xor eax,eax
.done:
        pop edi
        pop edx
        pop ecx
        pop ebx
        ret

; evaluate_based_literal(pointer,length,destination) -> output length in EAX.
; Supports &H hexadecimal, &O octal and &B binary literals. Values are
; accumulated as an unsigned 32-bit bit pattern and emitted through itoa_eax,
; matching classic BASIC behavior for high-bit values such as &HFFFFFFFF=-1.
evaluate_based_literal:
        push ebp
        mov ebp,esp
        push esi
        push edi
        push ebx
        push ecx
        push edx
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        mov edi,[ebp+16]
        call trim_span
        cmp ecx,3
        jb .bad
        cmp byte [esi],'&'
        jne .bad
        mov al,[esi+1]
        or al,20h
        mov ebx,16
        cmp al,'h'
        je .base_ready
        mov ebx,8
        cmp al,'o'
        je .base_ready
        mov ebx,2
        cmp al,'b'
        jne .bad
.base_ready:
        add esi,2
        sub ecx,2
        xor eax,eax                     ; accumulated 32-bit value
        xor edi,edi                     ; digit count
.next_digit:
        test ecx,ecx
        jz .finish
        mov dl,[esi]
        cmp dl,'0'
        jb .bad
        cmp dl,'9'
        jbe .decimal_digit
        mov dh,dl
        or dh,20h
        cmp dh,'a'
        jb .bad
        cmp dh,'f'
        ja .bad
        movzx edx,dh
        sub edx,'a'-10
        jmp .digit_ready
.decimal_digit:
        movzx edx,dl
        sub edx,'0'
.digit_ready:
        cmp edx,ebx
        jae .bad
        push edx                        ; preserve digit across MUL
        mul ebx                          ; EDX:EAX = EAX * base
        test edx,edx
        jnz .overflow_pop
        pop edx
        add eax,edx
        jc .overflow
        inc edi
        inc esi
        dec ecx
        jmp .next_digit
.overflow_pop:
        pop edx
.overflow:
        push msg_based_literal_overflow
        call set_runtime_error_z
        jmp .error_output
.finish:
        test edi,edi
        jz .bad
        mov edi,[ebp+16]
        call itoa_eax
        mov esi,[ebp+16]
        call strlen_esi
        jmp .done
.bad:
        push msg_bad_based_literal
        call set_runtime_error_z
.error_output:
        mov edi,[ebp+16]
        mov byte [edi],0
        xor eax,eax
.done:
        pop edx
        pop ecx
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 12

is_numeric_z:
        ; Canonical signed decimal test. Accepts one optional sign and one
        ; optional decimal point, but requires at least one digit.
        push ebp
        mov ebp,esp
        push esi
        push ebx
        push ecx
        mov esi,[ebp+8]
        cmp byte [esi],'-'
        jne .plus
        inc esi
        jmp .scan
.plus:
        cmp byte [esi],'+'
        jne .scan
        inc esi
.scan:
        xor ebx,ebx                    ; digits seen
        xor ecx,ecx                    ; decimal point seen
.loop:
        mov al,[esi]
        test al,al
        jz .finish
        cmp al,'0'
        jb .dot
        cmp al,'9'
        ja .dot
        inc ebx
        inc esi
        jmp .loop
.dot:
        cmp al,'.'
        jne .no
        test ecx,ecx
        jnz .no
        mov ecx,1
        inc esi
        jmp .loop
.finish:
        test ebx,ebx
        jz .no
        mov eax,1
        jmp .done
.no:
        xor eax,eax
.done:
        pop ecx
        pop ebx
        pop esi
        mov esp,ebp
        pop ebp
        ret 4

; ESI -> zero-terminated text, EAX=1 when a decimal point is present.
contains_decimal_z:
        push esi
.loop:
        mov al,[esi]
        test al,al
        jz .no
        cmp al,'.'
        je .yes
        inc esi
        jmp .loop
.yes:
        mov eax,1
        pop esi
        ret
.no:
        xor eax,eax
        pop esi
        ret

itoa_eax:
        ; signed EAX, EDI destination
        test eax,eax
        jns .positive
        mov byte [edi],'-'
        inc edi
        neg eax
.positive:
        call utoa_eax
        ret

; evaluate_primary_v013(pointer,length,destination), returns length in EAX.
; This is the proven v0.1.3 primary evaluator used by the recursive layer.
evaluate_primary_v013:
        push ebp
        mov ebp,esp
        push esi
        push edi
        push ebx
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        mov edi,[ebp+16]
        ; destination is frame-local in [ebp+16]
        call trim_span
        test ecx,ecx
        jz .empty

        cmp byte [esi],'"'
        je .string

        ; TIME$ and DATE$
        push token_time
        push ecx
        push esi
        call equals_keyword_span
        test eax,eax
        jnz .time
        push token_date
        push ecx
        push esi
        call equals_keyword_span
        test eax,eax
        jnz .date
        push token_timer
        push ecx
        push esi
        call equals_keyword_span
        test eax,eax
        jnz .timer
        push token_rnd
        push ecx
        push esi
        call equals_keyword_span
        test eax,eax
        jnz .rnd
        push token_pi
        push ecx
        push esi
        call equals_keyword_span
        test eax,eax
        jnz .pi_constant

        ; Functions.
        push func_readfile
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .readfile_func
        push func_readhex
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .readhex_func
        push func_len
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .len_func
        push func_left
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .left_func
        push func_right
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .right_func
        push func_mid
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .mid_func
        push func_ucase
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .ucase_func
        push func_lcase
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .lcase_func
        push func_trim
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .trim_func
        push func_ltrim
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .ltrim_func
        push func_rtrim
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .rtrim_func
        push func_html
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .html_func
        push func_json
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .json_func
        push func_str
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .str_func
        push func_val
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .val_func
        push func_cint
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .cint_func
        push func_clng
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .clng_func
        push func_cdbl
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .cdbl_func
        push func_csng
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .csng_func
        push func_hex
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .hex_func
        push func_oct
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .oct_func
        push func_abs
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .abs_func
        push func_sgn
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .sgn_func
        push func_int
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .int_func
        push func_fix
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .fix_func
        push func_sqr
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .sqr_func
        push func_sin
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .sin_func
        push func_cos
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .cos_func
        push func_tan
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .tan_func
        push func_atn
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .atn_func
        push func_log
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .log_func
        push func_exp
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .exp_func
        push func_asc
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .asc_func
        push func_chr
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .chr_func
        push func_instr
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .instr_func
        push func_space
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .space_func
        push func_string
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .string_repeat_func
        push func_lbound
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .lbound_func
        push func_ubound
        push ecx
        push esi
        call starts_function_span
        test eax,eax
        jnz .ubound_func

        ; BASIC base-prefixed integer literals: &H, &O and &B.
        ; Convert them to the evaluator's canonical signed decimal text so all
        ; existing arithmetic, comparisons and PRINT paths remain unchanged.
        cmp ecx,3
        jb .not_based_literal
        cmp byte [esi],'&'
        jne .not_based_literal
        mov al,[esi+1]
        or al,20h
        cmp al,'h'
        je .based_literal
        cmp al,'o'
        je .based_literal
        cmp al,'b'
        jne .not_based_literal
.based_literal:
        push dword [ebp+16]
        push ecx
        push esi
        call evaluate_based_literal
        jmp .done_len_eax
.not_based_literal:

        ; A dimensioned array element is resolved before the ordinary scalar
        ; identifier path.  Functions have already been recognized above, so
        ; NAME(expression) here unambiguously denotes an array reference.
        push var_build_name
        push ecx
        push esi
        call resolve_array_reference
        cmp eax,1
        je .array_identifier
        cmp eax,2
        je .array_error

        ; Plain identifier or numeric token.
        mov al,[esi]
        call is_identifier_start
        test eax,eax
        jz .copy_raw
        push esi
        push ecx
        call copy_span_to_name
        push var_build_name
        call get_variable_z
        test eax,eax
        jz .empty
        mov esi,eax
        mov edi,[ebp+16]
        call copy_z_limited_eval
        jmp .return_length

.array_identifier:
        push var_build_name
        call get_variable_z
        test eax,eax
        jz .array_default
        mov esi,eax
        mov edi,[ebp+16]
        call copy_z_limited_eval
        jmp .return_length

.array_default:
        mov edi,[ebp+16]
        cmp dword [array_last_is_string],0
        jne .array_default_string
        mov byte [edi],'0'
        mov byte [edi+1],0
        mov eax,1
        jmp .done_len_eax
.array_default_string:
        mov byte [edi],0
        xor eax,eax
        jmp .done_len_eax
.array_error:
        mov edi,[ebp+16]
        mov byte [edi],0
        xor eax,eax
        jmp .done_len_eax

.copy_raw:
        mov edi,[ebp+16]
        cmp ecx,EVAL_SIZE-1
        jbe .raw_size
        mov ecx,EVAL_SIZE-1
.raw_size:
        mov eax,ecx
        rep movsb
        mov byte [edi],0
        jmp .done_len_eax

.string:
        inc esi
        dec ecx
        mov edi,[ebp+16]
        xor ebx,ebx
.string_loop:
        test ecx,ecx
        jz .string_end
        mov al,[esi]
        inc esi
        dec ecx
        cmp al,'"'
        jne .string_store
        cmp byte [esi],'"'
        jne .string_end
        inc esi
        dec ecx
.string_store:
        cmp ebx,EVAL_SIZE-1
        jae .string_loop
        stosb
        inc ebx
        jmp .string_loop
.string_end:
        mov byte [edi],0
        mov eax,ebx
        jmp .done_len_eax

.readfile_func:
        call function_inner_span
        push 0
        push dword [ebp+16]
        push ecx
        push esi
        call evaluate_readfile_function
        jmp .done_len_eax

.readhex_func:
        call function_inner_span
        push 1
        push dword [ebp+16]
        push ecx
        push esi
        call evaluate_readfile_function
        jmp .done_len_eax

.len_func:
        call function_inner_span
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        mov esi,eval_temp
        call strlen_esi
        mov edi,[ebp+16]
        call utoa_eax
        jmp .return_length

.left_func:
        call function_inner_span
        push dword [ebp+16]
        push ecx
        push esi
        call evaluate_left_function
        jmp .done_len_eax

.right_func:
        call function_inner_span
        push dword [ebp+16]
        push ecx
        push esi
        call evaluate_right_function
        jmp .done_len_eax

.mid_func:
        call function_inner_span
        push dword [ebp+16]
        push ecx
        push esi
        call evaluate_mid_function
        jmp .done_len_eax

.ucase_func:
        call function_inner_span
        push 0
        push dword [ebp+16]
        push ecx
        push esi
        call evaluate_string_transform
        jmp .done_len_eax

.lcase_func:
        call function_inner_span
        push 1
        push dword [ebp+16]
        push ecx
        push esi
        call evaluate_string_transform
        jmp .done_len_eax

.trim_func:
        call function_inner_span
        push 2
        push dword [ebp+16]
        push ecx
        push esi
        call evaluate_string_transform
        jmp .done_len_eax

.ltrim_func:
        call function_inner_span
        push 3
        push dword [ebp+16]
        push ecx
        push esi
        call evaluate_string_transform
        jmp .done_len_eax

.rtrim_func:
        call function_inner_span
        push 4
        push dword [ebp+16]
        push ecx
        push esi
        call evaluate_string_transform
        jmp .done_len_eax

.html_func:
        call function_inner_span
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        mov esi,eval_temp
        mov edi,[ebp+16]
        call html_encode_z
        jmp .return_length

.json_func:
        call function_inner_span
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        mov esi,eval_temp
        mov edi,[ebp+16]
        call json_encode_z
        jmp .return_length

.str_func:
        call function_inner_span
        push dword [ebp+16]
        push ecx
        push esi
        call evaluate_atom
        jmp .done_len_eax

.val_func:
        ; VAL accepts a signed decimal prefix and stops at the first
        ; non-numeric character.  v0.1.31 preserves up to six fractional
        ; digits instead of truncating the result to an integer.
        call function_inner_span
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .conversion_error
        mov esi,eval_temp
        call parse_decimal_to_fpu
        test eax,eax
        jz .val_zero
        mov edi,[ebp+16]
        call format_fpu_decimal6
        jmp .done_len_eax
.val_zero:
        mov edi,[ebp+16]
        mov byte [edi],'0'
        mov byte [edi+1],0
        mov eax,1
        jmp .done_len_eax

.cint_func:
        mov dword [conversion_mode],0
        jmp .integer_conversion_common
.clng_func:
        mov dword [conversion_mode],1
.integer_conversion_common:
        ; CINT and CLNG use the x87 default round-to-nearest-even mode for
        ; decimal inputs.  Integer text takes the full signed 32-bit path.
        call function_inner_span
        push dword [conversion_mode]
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        pop eax
        mov [conversion_mode],eax
        cmp dword [runtime_error],0
        jne .conversion_error
        mov esi,eval_temp
        call contains_decimal_z
        test eax,eax
        jz .conversion_integer_text
        mov esi,eval_temp
        call parse_decimal_to_fpu
        test eax,eax
        jz .conversion_error
        fistp dword [fpu_integer_check]
        mov eax,[fpu_integer_check]
        cmp eax,80000000h
        je .conversion_range_error
        cmp dword [conversion_mode],0
        jne .conversion_write
        cmp eax,-32768
        jl .conversion_range_error
        cmp eax,32767
        jg .conversion_range_error
        jmp .conversion_write
.conversion_integer_text:
        mov esi,eval_temp
        call atoi_signed
        cmp dword [conversion_mode],0
        jne .conversion_write
        cmp eax,-32768
        jl .conversion_range_error
        cmp eax,32767
        jg .conversion_range_error
.conversion_write:
        mov edi,[ebp+16]
        call itoa_eax
        jmp .return_length
.conversion_range_error:
        push msg_conversion_range
        call set_runtime_error_z
        jmp .conversion_error

.cdbl_func:
.csng_func:
        ; The runtime stores numbers as canonical decimal text.  CDBL and
        ; CSNG therefore validate/evaluate the argument and preserve that
        ; canonical representation.
        call function_inner_span
        push dword [ebp+16]
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .conversion_error
        mov esi,[ebp+16]
        push esi
        call is_numeric_z
        test eax,eax
        jnz .conversion_passthrough
        mov edi,[ebp+16]
        mov byte [edi],'0'
        mov byte [edi+1],0
        mov eax,1
        jmp .done_len_eax
.conversion_passthrough:
        mov esi,[ebp+16]
        call strlen_esi
        jmp .done_len_eax

.conversion_error:
        finit
        mov edi,[ebp+16]
        mov byte [edi],0
        xor eax,eax
        jmp .done_len_eax

.hex_func:
        ; Convert the low 32 bits of a signed integer to uppercase hexadecimal.
        ; Negative values therefore use their two's-complement representation,
        ; matching the classic 32-bit BASIC convention.
        call function_inner_span
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .base_func_error
        mov esi,eval_temp
        call atoi_signed
        mov edi,[ebp+16]
        call utoa_hex_eax
        jmp .return_length

.oct_func:
        ; Convert the low 32 bits of a signed integer to octal text.
        call function_inner_span
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .base_func_error
        mov esi,eval_temp
        call atoi_signed
        mov edi,[ebp+16]
        call utoa_oct_eax
        jmp .return_length

.base_func_error:
        mov edi,[ebp+16]
        mov byte [edi],0
        xor eax,eax
        jmp .done_len_eax

.abs_func:
        call function_inner_span
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .numeric_func_error
        mov esi,eval_temp
        call contains_decimal_z
        test eax,eax
        jz .abs_integer
        mov esi,eval_temp
        call parse_decimal_to_fpu
        test eax,eax
        jz .numeric_func_error
        fabs
        mov edi,[ebp+16]
        call format_fpu_decimal6
        jmp .done_len_eax
.abs_integer:
        mov esi,eval_temp
        call atoi_signed
        test eax,eax
        jns .abs_write
        neg eax
.abs_write:
        mov edi,[ebp+16]
        call itoa_eax
        jmp .return_length

.sgn_func:
        call function_inner_span
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .numeric_func_error
        mov esi,eval_temp
        call contains_decimal_z
        test eax,eax
        jz .sgn_integer
        mov esi,eval_temp
        call parse_decimal_to_fpu
        test eax,eax
        jz .numeric_func_error
        fstp st0
        mov eax,[fpu_scaled_input]
        jmp .sgn_test
.sgn_integer:
        mov esi,eval_temp
        call atoi_signed
.sgn_test:
        test eax,eax
        jz .sgn_write
        js .sgn_negative
        mov eax,1
        jmp .sgn_write
.sgn_negative:
        mov eax,-1
.sgn_write:
        mov edi,[ebp+16]
        call itoa_eax
        jmp .return_length

.int_func:
        mov dword [intfix_mode],0
        jmp .intfix_common
.fix_func:
        mov dword [intfix_mode],1
.intfix_common:
        ; INT floors while FIX truncates toward zero. Decimal values are
        ; represented internally as signed micro-units.
        call function_inner_span
        push dword [intfix_mode]
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        pop eax
        mov [intfix_mode],eax
        cmp dword [runtime_error],0
        jne .numeric_func_error
        mov esi,eval_temp
        call contains_decimal_z
        test eax,eax
        jz .intfix_integer
        mov esi,eval_temp
        call parse_decimal_to_fpu
        test eax,eax
        jz .numeric_func_error
        fstp st0
        mov eax,[fpu_scaled_input]
        cdq
        mov ecx,1000000
        idiv ecx                        ; EAX truncates toward zero, EDX remainder
        ; The entry label is recorded before falling into this shared block.
        cmp dword [intfix_mode],0
        jne .intfix_write
        test edx,edx
        jz .intfix_write
        cmp dword [fpu_scaled_input],0
        jge .intfix_write
        dec eax                         ; INT(-2.9) = -3
        jmp .intfix_write
.intfix_integer:
        mov esi,eval_temp
        call atoi_signed
.intfix_write:
        mov edi,[ebp+16]
        call itoa_eax
        jmp .return_length

.sqr_func:
        call function_inner_span
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .numeric_func_error
        mov esi,eval_temp
        call contains_decimal_z
        test eax,eax
        jz .sqr_integer
        mov esi,eval_temp
        call parse_decimal_to_fpu
        test eax,eax
        jz .numeric_func_error
        cmp dword [fpu_scaled_input],0
        jl .sqr_negative_pop
        fsqrt
        mov edi,[ebp+16]
        call format_fpu_decimal6
        jmp .done_len_eax
.sqr_negative_pop:
        fstp st0
        jmp .sqr_negative
.sqr_integer:
        mov esi,eval_temp
        call atoi_signed
        test eax,eax
        js .sqr_negative
        call isqrt_eax
        mov edi,[ebp+16]
        call utoa_eax
        jmp .return_length
.sqr_negative:
        push msg_bad_sqr
        call set_runtime_error_z
.numeric_func_error:
        mov edi,[ebp+16]
        mov byte [edi],0
        xor eax,eax
        jmp .done_len_eax

        ; v0.1.31: x87-backed real functions and decimal arithmetic.  The general arithmetic engine
        ; remains integer based, but these functions accept signed decimal
        ; arguments (up to six fractional digits) and return canonical decimal
        ; text rounded to six places with trailing zeroes removed.
.sin_func:
        mov dword [fpu_operation],FPU_OP_SIN
        jmp .real_func
.cos_func:
        mov dword [fpu_operation],FPU_OP_COS
        jmp .real_func
.tan_func:
        mov dword [fpu_operation],FPU_OP_TAN
        jmp .real_func
.atn_func:
        mov dword [fpu_operation],FPU_OP_ATN
        jmp .real_func
.log_func:
        mov dword [fpu_operation],FPU_OP_LOG
        jmp .real_func
.exp_func:
        mov dword [fpu_operation],FPU_OP_EXP
.real_func:
        call function_inner_span

        ; A real function may contain another real function.  fpu_operation is
        ; global, so the recursive inner call temporarily replaces the outer
        ; operation (for example SIN(ATN(1)) changed SIN into ATN).  Preserve
        ; the outer operation on the CPU stack and restore it after the inner
        ; argument has been evaluated.
        push dword [fpu_operation]
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        pop eax
        mov [fpu_operation],eax

        cmp dword [runtime_error],0
        jne .real_func_error
        mov esi,eval_temp
        call parse_decimal_to_fpu
        test eax,eax
        jz .real_bad_argument

        mov eax,[fpu_operation]
        cmp eax,FPU_OP_SIN
        je .real_sin
        cmp eax,FPU_OP_COS
        je .real_cos
        cmp eax,FPU_OP_TAN
        je .real_tan
        cmp eax,FPU_OP_ATN
        je .real_atn
        cmp eax,FPU_OP_LOG
        je .real_log
        cmp eax,FPU_OP_EXP
        je .real_exp
        jmp .real_bad_argument
.real_sin:
        fsin
        jmp .real_write
.real_cos:
        fcos
        jmp .real_write
.real_tan:
        fptan
        fstp st0                       ; discard the 1.0 pushed by FPTAN
        jmp .real_write
.real_atn:
        fld1
        fpatan                         ; atan(argument / 1)
        jmp .real_write
.real_log:
        ; Reject zero and negative values before FYL2X.
        cmp dword [fpu_scaled_input],0
        jle .real_domain_error
        fldln2
        fxch st1
        fyl2x                          ; ln(2) * log2(argument)
        jmp .real_write
.real_exp:
        ; The decimal formatter uses a signed 32-bit micro-unit value. Keep
        ; EXP inside a range that can be represented after multiplication by
        ; one million.  -20..7 is ample for web scripting and deterministic.
        cmp dword [fpu_scaled_input],7000000
        jg .real_range_error_pop
        cmp dword [fpu_scaled_input],-20000000
        jl .real_range_error_pop
        fldl2e
        fmulp st1,st0                  ; x * log2(e)
        fld st0
        frndint
        fxch st1
        fsub st0,st1
        f2xm1
        fld1
        faddp st1,st0
        fscale
        fstp st1
        jmp .real_write
.real_write:
        mov edi,[ebp+16]
        call format_fpu_decimal6
        cmp dword [runtime_error],0
        jne .real_func_error
        jmp .done_len_eax
.real_range_error_pop:
        fstp st0
        push msg_real_range
        call set_runtime_error_z
        jmp .real_func_error
.real_domain_error:
        fstp st0
        push msg_real_domain
        call set_runtime_error_z
        jmp .real_func_error
.real_bad_argument:
        push msg_bad_real_argument
        call set_runtime_error_z
.real_func_error:
        finit
        mov edi,[ebp+16]
        mov byte [edi],0
        xor eax,eax
        jmp .done_len_eax

.asc_func:
        call function_inner_span
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .asc_error
        movzx eax,byte [eval_temp]
        test eax,eax
        jz .asc_empty
        mov edi,[ebp+16]
        call utoa_eax
        jmp .return_length
.asc_empty:
        push msg_bad_asc
        call set_runtime_error_z
.asc_error:
        mov edi,[ebp+16]
        mov byte [edi],0
        xor eax,eax
        jmp .done_len_eax

.chr_func:
        call function_inner_span
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        mov esi,eval_temp
        call atoi_signed
        mov edi,[ebp+16]
        mov [edi],al
        mov byte [edi+1],0
        mov eax,1
        jmp .done_len_eax

.instr_func:
        call function_inner_span
        push dword [ebp+16]
        push ecx
        push esi
        call evaluate_instr_function
        jmp .done_len_eax

.space_func:
        call function_inner_span
        push dword [ebp+16]
        push ecx
        push esi
        call evaluate_space_function
        jmp .done_len_eax

.string_repeat_func:
        call function_inner_span
        push dword [ebp+16]
        push ecx
        push esi
        call evaluate_string_repeat_function
        jmp .done_len_eax

.lbound_func:
        call function_inner_span
        push 0
        push dword [ebp+16]
        push ecx
        push esi
        call evaluate_array_bound
        jmp .done_len_eax

.ubound_func:
        call function_inner_span
        push 1
        push dword [ebp+16]
        push ecx
        push esi
        call evaluate_array_bound
        jmp .done_len_eax

.pi_constant:
        mov esi,text_pi
        mov edi,[ebp+16]
        call copy_z_limited_eval
        jmp .return_length

.rnd:
        ; Deterministic 32-bit LCG. The decimal-capable v0.1.31 evaluator exposes
        ; the sample as a canonical decimal fraction 0.000000..0.999999.
        mov eax,[rnd_seed]
        imul eax,1664525
        add eax,1013904223
        mov [rnd_seed],eax
        shr eax,8
        xor edx,edx
        mov ecx,1000000
        div ecx
        mov eax,edx
        mov edi,[ebp+16]
        mov byte [edi],'0'
        mov byte [edi+1],'.'
        add edi,2
        call six_decimal_digits
        mov byte [edi],0
        mov eax,8
        jmp .done_len_eax

.timer:
        push system_time
        call [GetLocalTime]
        movzx eax,word [system_time+8]     ; hour
        imul eax,3600
        movzx edx,word [system_time+10]    ; minute
        imul edx,60
        add eax,edx
        movzx edx,word [system_time+12]    ; second
        add eax,edx
        mov edi,[ebp+16]
        call utoa_eax
        jmp .return_length

.time:
        push system_time
        call [GetLocalTime]
        mov edi,[ebp+16]
        movzx eax,word [system_time+8]
        call two_digits
        mov byte [edi+2],':'
        movzx eax,word [system_time+10]
        lea edi,[edi+3]
        call two_digits
        mov byte [edi+2],':'
        movzx eax,word [system_time+12]
        lea edi,[edi+3]
        call two_digits
        mov byte [edi+2],0
        mov eax,8
        jmp .done_len_eax

.date:
        push system_time
        call [GetLocalTime]
        mov edi,[ebp+16]
        movzx eax,word [system_time+6]
        call two_digits
        mov byte [edi+2],'-'
        movzx eax,word [system_time+2]
        lea edi,[edi+3]
        call two_digits
        mov byte [edi+2],'-'
        movzx eax,word [system_time]
        lea edi,[edi+3]
        call four_digits
        mov byte [edi+4],0
        mov eax,10
        jmp .done_len_eax

.empty:
        mov edi,[ebp+16]
        mov byte [edi],0
        xor eax,eax
        jmp .done_len_eax

.return_length:
        mov esi,[ebp+16]
        call strlen_esi
.done_len_eax:
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 12

; Called after starts_function_span matched. Uses original ESI/ECX.
; Returns ESI/ECX for text inside outer parentheses.
function_inner_span:
        ; Find first '('.
.find_open:
        test ecx,ecx
        jz .none
        cmp byte [esi],'('
        je .open
        inc esi
        dec ecx
        jmp .find_open
.open:
        inc esi
        dec ecx
        call trim_span
        test ecx,ecx
        jz .none
        mov al,[esi+ecx-1]
        cmp al,')'
        jne .ready
        dec ecx
        call trim_span
.ready:
        ret
.none:
        xor ecx,ecx
        ret

; ----------------------------------------------------------------------------
; Search and string-construction functions (v0.1.23)
; ----------------------------------------------------------------------------

; evaluate_instr_function(inner_ptr,inner_len,destination)
; Implements the two-argument, case-sensitive BASIC form INSTR(text,find).
; The return value is one-based, or zero when the substring is absent.
evaluate_instr_function:
        push ebp
        mov ebp,esp
        sub esp,16
        push esi
        push edi
        push ebx
        push dword [ebp+12]
        push dword [ebp+8]
        call evaluate_two_string_args
        test eax,eax
        jz .error
        mov [ebp-4],eax                ; text buffer
        mov [ebp-8],edx                ; search buffer

        mov esi,[ebp-8]
        call strlen_esi
        mov [ebp-12],eax               ; search length
        test eax,eax
        jz .first_position

        mov esi,[ebp-4]
        call strlen_esi
        mov [ebp-16],eax               ; text length
        cmp eax,[ebp-12]
        jb .not_found

        xor ebx,ebx                    ; zero-based candidate offset
.search:
        mov esi,[ebp-4]
        add esi,ebx
        mov edi,[ebp-8]
        mov ecx,[ebp-12]
        repe cmpsb
        je .found
        inc ebx
        mov eax,[ebp-16]
        sub eax,[ebp-12]
        cmp ebx,eax
        jbe .search
.not_found:
        xor eax,eax
        jmp .emit
.first_position:
        mov eax,1
        jmp .emit
.found:
        lea eax,[ebx+1]
.emit:
        mov edi,[ebp+16]
        call utoa_eax
        mov esi,[ebp+16]
        call strlen_esi
        sub dword [eval_work_depth],2
        jmp .done
.error:
        mov edi,[ebp+16]
        mov byte [edi],0
        xor eax,eax
.done:
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 12

; evaluate_space_function(inner_ptr,inner_len,destination)
; SPACE$(count) creates count ASCII spaces. Negative counts are rejected and
; output is limited by the ordinary evaluator buffer size.
evaluate_space_function:
        push ebp
        mov ebp,esp
        push esi
        push edi
        push ebx
        call alloc_eval_slot
        mov ebx,eax
        push eax
        push dword [ebp+12]
        push dword [ebp+8]
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .error_slot
        mov esi,ebx
        call atoi_signed
        test eax,eax
        js .bad_count
        cmp eax,EVAL_SIZE-1
        jbe .count_ready
        mov eax,EVAL_SIZE-1
.count_ready:
        mov ecx,eax
        mov ebx,eax
        mov edi,[ebp+16]
        mov al,' '
        rep stosb
        mov byte [edi],0
        mov eax,ebx
        dec dword [eval_work_depth]
        jmp .done
.bad_count:
        push msg_bad_space
        call set_runtime_error_z
.error_slot:
        dec dword [eval_work_depth]
        mov edi,[ebp+16]
        mov byte [edi],0
        xor eax,eax
.done:
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 12

; evaluate_string_repeat_function(inner_ptr,inner_len,destination)
; STRING$(count,text) repeats the first character of text count times.
evaluate_string_repeat_function:
        push ebp
        mov ebp,esp
        sub esp,8
        push esi
        push edi
        push ebx
        push dword [ebp+12]
        push dword [ebp+8]
        call evaluate_two_string_args
        test eax,eax
        jz .error
        mov [ebp-4],eax                ; count expression buffer
        mov [ebp-8],edx                ; character expression buffer
        mov esi,[ebp-4]
        call atoi_signed
        test eax,eax
        js .bad_count
        cmp eax,EVAL_SIZE-1
        jbe .count_ready
        mov eax,EVAL_SIZE-1
.count_ready:
        mov ebx,eax
        mov esi,[ebp-8]
        mov al,[esi]
        test al,al
        jz .bad_character
        mov edi,[ebp+16]
        mov ecx,ebx
        rep stosb
        mov byte [edi],0
        mov eax,ebx
        sub dword [eval_work_depth],2
        jmp .done
.bad_count:
        push msg_bad_string
        call set_runtime_error_z
        jmp .error_release
.bad_character:
        push msg_bad_string
        call set_runtime_error_z
.error_release:
        sub dword [eval_work_depth],2
.error:
        mov edi,[ebp+16]
        mov byte [edi],0
        xor eax,eax
.done:
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 12

; ----------------------------------------------------------------------------
; Character-code conversion (v0.1.23)
; ----------------------------------------------------------------------------
; ASC(text) returns the unsigned byte value of the first character. CHR$()
; remains compatible with the earlier stable core and accepts an expression.

; ----------------------------------------------------------------------------
; Case conversion and whitespace trimming (v0.1.23)
; ----------------------------------------------------------------------------

; evaluate_string_transform(inner_ptr,inner_len,destination,mode)
; mode 0=UCASE$, 1=LCASE$, 2=TRIM$, 3=LTRIM$, 4=RTRIM$.
; The argument is evaluated into a private evaluator slot so nested calls do
; not overwrite the outer destination.
evaluate_string_transform:
        push ebp
        mov ebp,esp
        sub esp,16
        push esi
        push edi
        push ebx
        call alloc_eval_slot
        mov [ebp-4],eax
        push eax
        push dword [ebp+12]
        push dword [ebp+8]
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .error

        mov eax,[ebp+20]
        cmp eax,0
        je .uppercase
        cmp eax,1
        je .lowercase

        ; Trimming modes. Establish [start,end) in ESI/EBX.
        mov esi,[ebp-4]
        call strlen_esi
        mov ebx,esi
        add ebx,eax
        mov eax,[ebp+20]
        cmp eax,4
        je .trim_right
.trim_left:
        cmp esi,ebx
        jae .trim_right
        mov al,[esi]
        cmp al,' '
        je .skip_left
        cmp al,9
        jne .trim_right
.skip_left:
        inc esi
        jmp .trim_left
.trim_right:
        mov eax,[ebp+20]
        cmp eax,3
        je .copy_trimmed
.trim_right_loop:
        cmp ebx,esi
        jbe .copy_trimmed
        mov al,[ebx-1]
        cmp al,' '
        je .skip_right
        cmp al,9
        jne .copy_trimmed
.skip_right:
        dec ebx
        jmp .trim_right_loop
.copy_trimmed:
        mov ecx,ebx
        sub ecx,esi
        cmp ecx,EVAL_SIZE-1
        jbe .trim_size_ok
        mov ecx,EVAL_SIZE-1
.trim_size_ok:
        mov eax,ecx
        mov edi,[ebp+16]
        rep movsb
        mov byte [edi],0
        jmp .success

.uppercase:
        mov esi,[ebp-4]
        mov edi,[ebp+16]
        xor ecx,ecx
.upper_loop:
        cmp ecx,EVAL_SIZE-1
        jae .case_finish
        lodsb
        test al,al
        jz .case_finish
        cmp al,'a'
        jb .upper_store
        cmp al,'z'
        ja .upper_store
        sub al,20h
.upper_store:
        stosb
        inc ecx
        jmp .upper_loop

.lowercase:
        mov esi,[ebp-4]
        mov edi,[ebp+16]
        xor ecx,ecx
.lower_loop:
        cmp ecx,EVAL_SIZE-1
        jae .case_finish
        lodsb
        test al,al
        jz .case_finish
        cmp al,'A'
        jb .lower_store
        cmp al,'Z'
        ja .lower_store
        add al,20h
.lower_store:
        stosb
        inc ecx
        jmp .lower_loop
.case_finish:
        mov byte [edi],0
        mov eax,ecx
.success:
        dec dword [eval_work_depth]
        jmp .done
.error:
        dec dword [eval_work_depth]
        mov edi,[ebp+16]
        mov byte [edi],0
        xor eax,eax
.done:
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 16

; ----------------------------------------------------------------------------
; String slicing functions (v0.1.14)
; ----------------------------------------------------------------------------

; find_top_level_comma(pointer,length) -> EAX pointer or zero.
; Quotes and nested parentheses are respected, allowing expressions and nested
; function calls inside LEFT$(), RIGHT$() and MID$().
find_top_level_comma:
        push ebp
        mov ebp,esp
        push esi
        push ecx
        push ebx
        push edx
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        xor ebx,ebx                    ; quote state
        xor edx,edx                    ; parenthesis depth
.scan:
        test ecx,ecx
        jz .none
        mov al,[esi]
        cmp al,'"'
        jne .not_quote
        ; BASIC doubles a quote inside a string: "".
        test ebx,ebx
        jz .toggle_quote
        cmp ecx,1
        jbe .toggle_quote
        cmp byte [esi+1],'"'
        jne .toggle_quote
        add esi,2
        sub ecx,2
        jmp .scan
.toggle_quote:
        xor ebx,1
        jmp .advance
.not_quote:
        test ebx,ebx
        jnz .advance
        cmp al,'('
        jne .not_open
        inc edx
        jmp .advance
.not_open:
        cmp al,')'
        jne .not_close
        test edx,edx
        jz .advance
        dec edx
        jmp .advance
.not_close:
        cmp al,','
        jne .advance
        test edx,edx
        jnz .advance
        mov eax,esi
        jmp .done
.advance:
        inc esi
        dec ecx
        jmp .scan
.none:
        xor eax,eax
.done:
        pop edx
        pop ebx
        pop ecx
        pop esi
        mov esp,ebp
        pop ebp
        ret 8

; evaluate_two_string_args(inner_ptr,inner_len)
; Returns EAX=first evaluated buffer, EDX=second evaluated buffer.
; The caller must release two evaluator slots by subtracting 2 from
; eval_work_depth. On error EAX=EDX=0 and runtime_error is set.
evaluate_two_string_args:
        push ebp
        mov ebp,esp
        sub esp,20
        push esi
        push edi
        push ebx
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        push ecx
        push esi
        call find_top_level_comma
        test eax,eax
        jnz .have_comma
        push msg_bad_substring
        call set_runtime_error_z
        xor eax,eax
        xor edx,edx
        jmp .done
.have_comma:
        mov [ebp-4],eax                ; comma pointer
        mov edx,eax
        sub edx,esi
        mov [ebp-8],edx                ; first span length
        lea ebx,[eax+1]
        mov edx,[ebp+8]
        add edx,[ebp+12]
        sub edx,ebx
        mov [ebp-12],ebx               ; second span pointer
        mov [ebp-16],edx               ; second span length

        call alloc_eval_slot
        mov [ebp-20],eax               ; first buffer
        push eax
        push dword [ebp-8]
        push dword [ebp+8]
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .failure_one

        call alloc_eval_slot
        mov edi,eax                    ; second buffer
        push eax
        push dword [ebp-16]
        push dword [ebp-12]
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .failure_two

        mov eax,[ebp-20]
        mov edx,edi
        jmp .done
.failure_two:
        dec dword [eval_work_depth]
.failure_one:
        dec dword [eval_work_depth]
        xor eax,eax
        xor edx,edx
.done:
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 8

; LEFT$(text,count)
evaluate_left_function:
        push ebp
        mov ebp,esp
        sub esp,8
        push esi
        push edi
        push ebx
        push dword [ebp+12]
        push dword [ebp+8]
        call evaluate_two_string_args
        test eax,eax
        jz .error
        mov [ebp-4],eax                ; text buffer
        mov esi,edx
        call atoi_signed
        mov ebx,eax                    ; requested count
        test ebx,ebx
        jns .count_nonnegative
        xor ebx,ebx
.count_nonnegative:
        mov esi,[ebp-4]
        call strlen_esi
        cmp ebx,eax
        jbe .count_ready
        mov ebx,eax
.count_ready:
        mov esi,[ebp-4]
        mov edi,[ebp+16]
        mov ecx,ebx
        rep movsb
        mov byte [edi],0
        mov eax,ebx
        sub dword [eval_work_depth],2
        jmp .done
.error:
        mov edi,[ebp+16]
        mov byte [edi],0
        xor eax,eax
.done:
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 12

; RIGHT$(text,count)
evaluate_right_function:
        push ebp
        mov ebp,esp
        sub esp,8
        push esi
        push edi
        push ebx
        push dword [ebp+12]
        push dword [ebp+8]
        call evaluate_two_string_args
        test eax,eax
        jz .error
        mov [ebp-4],eax
        mov esi,edx
        call atoi_signed
        mov ebx,eax
        test ebx,ebx
        jns .count_nonnegative
        xor ebx,ebx
.count_nonnegative:
        mov esi,[ebp-4]
        call strlen_esi
        mov [ebp-8],eax                ; source length
        cmp ebx,eax
        jbe .count_ready
        mov ebx,eax
.count_ready:
        mov esi,[ebp-4]
        add esi,[ebp-8]
        sub esi,ebx
        mov edi,[ebp+16]
        mov ecx,ebx
        rep movsb
        mov byte [edi],0
        mov eax,ebx
        sub dword [eval_work_depth],2
        jmp .done
.error:
        mov edi,[ebp+16]
        mov byte [edi],0
        xor eax,eax
.done:
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 12

; MID$(text,start[,length]) -- BASIC-compatible 1-based start position.
evaluate_mid_function:
        push ebp
        mov ebp,esp
        sub esp,40
        push esi
        push edi
        push ebx
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        push ecx
        push esi
        call find_top_level_comma
        test eax,eax
        jnz .first_comma
        push msg_bad_substring
        call set_runtime_error_z
        jmp .error_no_slots
.first_comma:
        mov [ebp-4],eax                ; first comma
        mov edx,eax
        sub edx,esi
        mov [ebp-8],edx                ; text length
        lea ebx,[eax+1]
        mov edx,[ebp+8]
        add edx,[ebp+12]
        sub edx,ebx
        mov [ebp-12],ebx               ; remaining pointer
        mov [ebp-16],edx               ; remaining length

        push edx
        push ebx
        call find_top_level_comma
        mov [ebp-20],eax               ; optional second comma

        call alloc_eval_slot
        mov [ebp-24],eax               ; text buffer
        push eax
        push dword [ebp-8]
        push dword [ebp+8]
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .error_one_slot

        call alloc_eval_slot
        mov [ebp-28],eax               ; start buffer
        mov eax,[ebp-20]
        test eax,eax
        jz .start_to_end
        mov edx,eax
        sub edx,[ebp-12]
        push dword [ebp-28]
        push edx
        push dword [ebp-12]
        call evaluate_atom
        jmp .start_done
.start_to_end:
        push dword [ebp-28]
        push dword [ebp-16]
        push dword [ebp-12]
        call evaluate_atom
.start_done:
        cmp dword [runtime_error],0
        jne .error_two_slots
        mov esi,[ebp-28]
        call atoi_signed
        mov [ebp-32],eax               ; 1-based start

        mov dword [ebp-36],7FFFFFFFh   ; omitted length means to end
        mov eax,[ebp-20]
        test eax,eax
        jz .have_arguments
        call alloc_eval_slot
        mov [ebp-40],eax               ; length buffer
        lea esi,[eax+1]
        mov esi,[ebp-20]
        inc esi
        mov ecx,[ebp+8]
        add ecx,[ebp+12]
        sub ecx,esi
        push dword [ebp-40]
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .error_three_slots
        mov esi,[ebp-40]
        call atoi_signed
        mov [ebp-36],eax
        dec dword [eval_work_depth]     ; release optional length slot

.have_arguments:
        mov esi,[ebp-24]
        call strlen_esi
        mov ebx,eax                    ; source length
        mov eax,[ebp-32]
        cmp eax,1
        jge .start_positive
        mov eax,1
.start_positive:
        dec eax                        ; zero-based offset
        cmp eax,ebx
        jb .inside
        mov edi,[ebp+16]
        mov byte [edi],0
        xor eax,eax
        sub dword [eval_work_depth],2
        jmp .done
.inside:
        mov edx,ebx
        sub edx,eax                    ; available bytes
        mov ecx,[ebp-36]
        test ecx,ecx
        jns .length_nonnegative
        xor ecx,ecx
.length_nonnegative:
        cmp ecx,edx
        jbe .length_ready
        mov ecx,edx
.length_ready:
        mov esi,[ebp-24]
        add esi,eax
        mov edi,[ebp+16]
        mov ebx,ecx                    ; preserve result length
        rep movsb
        mov byte [edi],0
        mov eax,ebx
        sub dword [eval_work_depth],2
        jmp .done

.error_three_slots:
        dec dword [eval_work_depth]
.error_two_slots:
        dec dword [eval_work_depth]
.error_one_slot:
        dec dword [eval_work_depth]
.error_no_slots:
        mov edi,[ebp+16]
        mov byte [edi],0
        xor eax,eax
.done:
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 12

; ----------------------------------------------------------------------------
; DATA, READ and RESTORE (v0.1.12)
; ----------------------------------------------------------------------------

; prepare_data_table
; Scans the active BASIC block once, preserving DATA source order.  DATA items
; are stored as zero-terminated textual values; quoted strings lose their outer
; quotes and doubled quotes are collapsed.
prepare_data_table:
        push ebp
        mov ebp,esp
        sub esp,16
        pushad
        mov dword [data_item_count],0
        mov dword [data_read_index],0
        mov dword [data_initialized],0
        mov esi,[active_program_start]
        mov edi,[active_program_end]
.scan_line:
        cmp esi,edi
        jae .complete
        mov [ebp-4],esi                  ; raw line start
        mov ebx,esi
.find_eol:
        cmp ebx,edi
        jae .line_ready
        mov al,[ebx]
        cmp al,13
        je .line_ready
        cmp al,10
        je .line_ready
        inc ebx
        jmp .find_eol
.line_ready:
        mov [ebp-8],ebx                  ; raw line end
        mov edx,ebx
.skip_eol:
        cmp edx,edi
        jae .after_eol
        mov al,[edx]
        cmp al,13
        je .advance_eol
        cmp al,10
        jne .after_eol
.advance_eol:
        inc edx
        jmp .skip_eol
.after_eol:
        mov [ebp-12],edx                 ; next line
        mov esi,[ebp-4]
        mov ecx,[ebp-8]
        sub ecx,esi
        call trim_span
        test ecx,ecx
        jz .advance_line
        call strip_statement_prefix
        test ecx,ecx
        jz .advance_line
        cmp byte [esi],39
        je .advance_line
        push keyword_data
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jz .advance_line
        add esi,eax
        sub ecx,eax
        call trim_span
        push ecx
        push esi
        call parse_data_line
        cmp dword [runtime_error],0
        jne .done
.advance_line:
        mov esi,[ebp-12]
        jmp .scan_line
.complete:
        mov dword [data_initialized],1
.done:
        popad
        mov esp,ebp
        pop ebp
        ret

; parse_data_line(pointer,length)
parse_data_line:
        push ebp
        mov ebp,esp
        pushad
        mov esi,[ebp+8]
        mov edi,esi
        add edi,[ebp+12]
        mov ebx,esi                       ; current item start
        xor edx,edx                       ; quote state
.scan:
        cmp esi,edi
        jae .last
        mov al,[esi]
        cmp al,'"'
        jne .not_quote
        xor edx,1
        inc esi
        jmp .scan
.not_quote:
        test edx,edx
        jnz .advance
        cmp al,','
        je .emit
.advance:
        inc esi
        jmp .scan
.emit:
        mov eax,esi
        sub eax,ebx
        push eax
        push ebx
        call store_data_item
        cmp dword [runtime_error],0
        jne .done
        inc esi
        mov ebx,esi
        jmp .scan
.last:
        mov eax,esi
        sub eax,ebx
        push eax
        push ebx
        call store_data_item
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; store_data_item(pointer,length)
store_data_item:
        push ebp
        mov ebp,esp
        pushad
        mov eax,[data_item_count]
        cmp eax,MAX_DATA_ITEMS
        jae .too_many
        imul eax,DATA_ITEM_SIZE
        lea edi,[data_items+eax]
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        xor edx,edx                       ; quoted flag
        cmp ecx,2
        jb .copy
        cmp byte [esi],'"'
        jne .copy
        cmp byte [esi+ecx-1],'"'
        jne .copy
        inc esi
        sub ecx,2
        mov edx,1
.copy:
        xor ebx,ebx
.copy_loop:
        test ecx,ecx
        jz .finish
        cmp ebx,DATA_ITEM_SIZE-1
        jae .finish
        mov al,[esi]
        test edx,edx
        jz .store
        cmp al,'"'
        jne .store
        cmp ecx,2
        jb .store
        cmp byte [esi+1],'"'
        jne .store
        mov [edi+ebx],al
        inc ebx
        add esi,2
        sub ecx,2
        jmp .copy_loop
.store:
        mov [edi+ebx],al
        inc ebx
        inc esi
        dec ecx
        jmp .copy_loop
.finish:
        mov byte [edi+ebx],0
        inc dword [data_item_count]
        jmp .done
.too_many:
        push msg_data_limit
        call set_runtime_error_z
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; execute_read(pointer,length)
; Supports comma-separated scalar and one-dimensional array targets.
execute_read:
        push ebp
        mov ebp,esp
        pushad
        cmp dword [data_initialized],0
        jne .initialized
        call prepare_data_table
.initialized:
        cmp dword [runtime_error],0
        jne .done
        mov esi,[ebp+8]
        mov edi,esi
        add edi,[ebp+12]
        mov ebx,esi
        xor edx,edx                       ; parenthesis depth
        cmp esi,edi
        jae .bad
.scan:
        cmp esi,edi
        jae .last
        mov al,[esi]
        cmp al,'('
        jne .not_open
        inc edx
        jmp .advance
.not_open:
        cmp al,')'
        jne .separator
        test edx,edx
        jz .advance
        dec edx
        jmp .advance
.separator:
        test edx,edx
        jnz .advance
        cmp al,','
        je .emit
.advance:
        inc esi
        jmp .scan
.emit:
        mov eax,esi
        sub eax,ebx
        push eax
        push ebx
        call read_one_target
        cmp dword [runtime_error],0
        jne .done
        inc esi
        mov ebx,esi
        jmp .scan
.last:
        mov eax,esi
        sub eax,ebx
        push eax
        push ebx
        call read_one_target
        jmp .done
.bad:
        push msg_bad_read
        call set_runtime_error_z
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; read_one_target(pointer,length)
read_one_target:
        push ebp
        mov ebp,esp
        pushad
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        test ecx,ecx
        jz .bad
        push assignment_name
        push ecx
        push esi
        call resolve_array_reference
        cmp eax,1
        je .target_ready
        cmp eax,2
        je .done
        push assignment_name
        push ecx
        push esi
        call normalize_name_span_to
        cmp byte [assignment_name],0
        je .bad
.target_ready:
        mov eax,[data_read_index]
        cmp eax,[data_item_count]
        jae .out_of_data
        imul eax,DATA_ITEM_SIZE
        add eax,data_items
        push eax
        push assignment_name
        call set_variable_z
        inc dword [data_read_index]
        jmp .done
.bad:
        push msg_bad_read
        call set_runtime_error_z
        jmp .done
.out_of_data:
        push msg_out_of_data
        call set_runtime_error_z
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; execute_restore(pointer,length)
; This incremental release supports RESTORE without a label.
execute_restore:
        push ebp
        mov ebp,esp
        pushad
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        test ecx,ecx
        jnz .label_not_supported
        mov dword [data_read_index],0
        jmp .done
.label_not_supported:
        push msg_restore_label
        call set_runtime_error_z
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; ----------------------------------------------------------------------------
; SWAP statement (v0.1.12)
; ----------------------------------------------------------------------------

; execute_swap(pointer,length)
; Exchanges the values of two scalar variables or one-dimensional array
; elements. Both references and both values are resolved before either target
; is modified, so computed array indices are stable during the exchange.
execute_swap:
        push ebp
        mov ebp,esp
        sub esp,24
        pushad
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        test ecx,ecx
        jz .bad
        mov [ebp-4],esi                  ; complete trimmed span start
        lea eax,[esi+ecx]
        mov [ebp-8],eax                  ; complete trimmed span end
        mov dword [ebp-12],0             ; top-level comma pointer
        mov dword [ebp-16],0             ; parenthesis depth
        mov dword [ebp-20],0             ; inside quoted string

.scan:
        cmp esi,[ebp-8]
        jae .scan_done
        mov al,[esi]
        cmp al,'"'
        jne .not_quote
        xor dword [ebp-20],1
        inc esi
        jmp .scan
.not_quote:
        cmp dword [ebp-20],0
        jne .advance
        cmp al,'('
        jne .not_open
        inc dword [ebp-16]
        jmp .advance
.not_open:
        cmp al,')'
        jne .not_close
        cmp dword [ebp-16],0
        jle .bad
        dec dword [ebp-16]
        jmp .advance
.not_close:
        cmp al,','
        jne .advance
        cmp dword [ebp-16],0
        jne .advance
        cmp dword [ebp-12],0
        jne .bad                         ; more than two SWAP operands
        mov [ebp-12],esi
.advance:
        inc esi
        jmp .scan

.scan_done:
        cmp dword [ebp-20],0
        jne .bad
        cmp dword [ebp-16],0
        jne .bad
        mov eax,[ebp-12]
        test eax,eax
        jz .bad

        ; Trim and remember both operand spans.
        mov esi,[ebp-4]
        mov ecx,eax
        sub ecx,esi
        call trim_span
        test ecx,ecx
        jz .bad
        mov [ebp-4],esi                  ; left pointer
        mov [ebp-8],ecx                  ; left length

        mov esi,[ebp-12]
        inc esi
        mov ecx,[ebp+8]
        add ecx,[ebp+12]
        sub ecx,esi
        call trim_span
        test ecx,ecx
        jz .bad
        mov [ebp-12],esi                 ; right pointer
        mov [ebp-16],ecx                 ; right length

        ; Resolve both writable targets first.
        push swap_name_a
        push dword [ebp-8]
        push dword [ebp-4]
        call resolve_swap_target
        test eax,eax
        jz .done

        push swap_name_b
        push dword [ebp-16]
        push dword [ebp-12]
        call resolve_swap_target
        test eax,eax
        jz .done

        ; Read both original values before writing either one.
        mov dword [eval_work_depth],0
        push swap_value_a
        push dword [ebp-8]
        push dword [ebp-4]
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .done

        mov dword [eval_work_depth],0
        push swap_value_b
        push dword [ebp-16]
        push dword [ebp-12]
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .done

        push swap_value_b
        push swap_name_a
        call set_variable_z
        push swap_value_a
        push swap_name_b
        call set_variable_z
        jmp .done

.bad:
        push msg_bad_swap
        call set_runtime_error_z
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; resolve_swap_target(pointer,length,destination_name) -> EAX boolean.
; Array references are converted to their canonical element names. Scalars are
; normalized in the same manner as assignment and READ targets.
resolve_swap_target:
        push ebp
        mov ebp,esp
        push esi
        push ecx
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        test ecx,ecx
        jz .bad
        push dword [ebp+16]
        push ecx
        push esi
        call resolve_array_reference
        cmp eax,1
        je .yes
        cmp eax,2
        je .no                           ; resolver already set the error
        push dword [ebp+16]
        push ecx
        push esi
        call normalize_name_span_to
        mov eax,[ebp+16]
        cmp byte [eax],0
        je .bad
.yes:
        mov eax,1
        jmp .done
.bad:
        push msg_bad_swap
        call set_runtime_error_z
.no:
        xor eax,eax
.done:
        pop ecx
        pop esi
        mov esp,ebp
        pop ebp
        ret 12

; ----------------------------------------------------------------------------
; OPTION BASE and DIM / one-dimensional arrays (extended in v0.1.31)
; ----------------------------------------------------------------------------

; execute_option_base(pointer,length)
; Accepts exactly OPTION BASE 0 or OPTION BASE 1.  The declaration must
; precede the first array DIM.  Explicit lower bounds always override it.
execute_option_base:
        push ebp
        mov ebp,esp
        push esi
        push ecx
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        cmp dword [array_count],0
        jne .too_late
        cmp ecx,1
        jne .bad
        cmp byte [esi],'0'
        je .base_zero
        cmp byte [esi],'1'
        jne .bad
        mov dword [option_base],1
        jmp .done
.base_zero:
        mov dword [option_base],0
        jmp .done
.too_late:
        push msg_option_base_late
        call set_runtime_error_z
        jmp .done
.bad:
        push msg_bad_option_base
        call set_runtime_error_z
.done:
        pop ecx
        pop esi
        mov esp,ebp
        pop ebp
        ret 8


; execute_dim(pointer,length)
; Supports comma-separated declarations at top level:
;     DIM A(10), B$(4), X AS INTEGER
;     DIM A(2 TO 5), S$(1 TO 3), T AS STRING
execute_dim:
        push ebp
        mov ebp,esp
        sub esp,16
        pushad
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        test ecx,ecx
        jz .bad
        mov [ebp-4],esi                  ; current declaration start
        lea eax,[esi+ecx]
        mov [ebp-8],eax                  ; end of complete DIM span
        mov edi,esi                      ; scanner
        xor ebx,ebx                      ; parenthesis depth
        xor edx,edx                      ; quote state
.scan:
        cmp edi,[ebp-8]
        jae .last
        mov al,[edi]
        cmp al,'"'
        jne .not_quote
        xor edx,1
        inc edi
        jmp .scan
.not_quote:
        test edx,edx
        jnz .advance
        cmp al,'('
        jne .not_open
        inc ebx
        jmp .advance
.not_open:
        cmp al,')'
        jne .not_close
        test ebx,ebx
        jz .bad
        dec ebx
        jmp .advance
.not_close:
        cmp al,','
        jne .advance
        test ebx,ebx
        jnz .advance
        mov eax,edi
        sub eax,[ebp-4]
        push eax
        push dword [ebp-4]
        call execute_dim_one
        cmp dword [runtime_error],0
        jne .done
        lea eax,[edi+1]
        mov [ebp-4],eax
.advance:
        inc edi
        jmp .scan
.last:
        test ebx,ebx
        jnz .bad
        test edx,edx
        jnz .bad
        mov eax,[ebp-8]
        sub eax,[ebp-4]
        push eax
        push dword [ebp-4]
        call execute_dim_one
        jmp .done
.bad:
        cmp dword [runtime_error],0
        jne .done
        push msg_bad_dim
        call set_runtime_error_z
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; execute_dim_one(pointer,length)
; One declaration after top-level comma splitting.  AS type annotations are
; accepted; AS STRING creates string storage even without a trailing '$'.
execute_dim_one:
        push ebp
        mov ebp,esp
        sub esp,40
        pushad
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        test ecx,ecx
        jz .bad
        call strip_dim_type_clause
        mov [ebp-36],eax                 ; 0=no AS, 1=numeric AS, 2=AS STRING
        test ecx,ecx
        jz .bad
        mov [ebp-12],esi                 ; declaration pointer
        mov [ebp-16],ecx                 ; declaration length

        xor ebx,ebx
.scan_open:
        cmp ebx,ecx
        jae .scalar
        cmp byte [esi+ebx],'('
        je .have_open
        inc ebx
        jmp .scan_open

.have_open:
        mov [ebp-4],ebx                  ; opening-parenthesis offset
        test ebx,ebx
        jz .bad
        cmp byte [esi+ecx-1],')'
        jne .bad

        ; Normalize the array base name.
        push array_name_temp
        push ebx
        push esi
        call normalize_name_span_to
        cmp byte [array_name_temp],0
        je .bad

        ; Locate and trim the complete bounds span.
        mov esi,[ebp-12]
        mov ecx,[ebp-16]
        mov ebx,[ebp-4]
        lea esi,[esi+ebx+1]
        sub ecx,ebx
        sub ecx,2
        call trim_span
        test ecx,ecx
        jz .bad
        mov [ebp-24],esi                 ; bounds pointer
        mov [ebp-28],ecx                 ; bounds length

        push ecx
        push esi
        call find_dim_to
        test eax,eax
        jz .implicit_base

        ; Explicit lower bound: lower TO upper.
        mov [ebp-32],eax                 ; pointer to TO
        mov ecx,eax
        sub ecx,[ebp-24]
        push ecx
        push dword [ebp-24]
        call evaluate_dim_integer
        test edx,edx
        jz .done
        mov [ebp-20],eax                 ; lower

        mov esi,[ebp-32]
        add esi,2
        mov ecx,[ebp-24]
        add ecx,[ebp-28]
        sub ecx,esi
        push ecx
        push esi
        call evaluate_dim_integer
        test edx,edx
        jz .done
        mov [ebp-8],eax                  ; upper
        jmp .validate_bounds

.implicit_base:
        mov eax,[option_base]
        mov [ebp-20],eax
        push dword [ebp-28]
        push dword [ebp-24]
        call evaluate_dim_integer
        test edx,edx
        jz .done
        mov [ebp-8],eax

.validate_bounds:
        mov eax,[ebp-20]
        cmp eax,-MAX_ARRAY_INDEX
        jl .bad_size
        cmp eax,MAX_ARRAY_INDEX
        jg .bad_size
        mov edx,[ebp-8]
        cmp edx,-MAX_ARRAY_INDEX
        jl .bad_size
        cmp edx,MAX_ARRAY_INDEX
        jg .bad_size
        cmp edx,eax
        jl .bad_size
        sub edx,eax
        cmp edx,MAX_ARRAY_INDEX
        jg .bad_size

        push array_name_temp
        call find_array_z
        cmp eax,-1
        jne .store_metadata
        mov eax,[array_count]
        cmp eax,MAX_ARRAYS
        jae .too_many
        mov ebx,eax
        inc dword [array_count]
        imul eax,VAR_NAME_SIZE
        lea edi,[array_names+eax]
        mov esi,array_name_temp
        call copy_z_limited_name
        mov eax,ebx
.store_metadata:
        mov ebx,eax
        mov eax,[ebp-20]
        mov [array_lower+ebx*4],eax
        mov eax,[ebp-8]
        mov [array_upper+ebx*4],eax

        xor edx,edx
        cmp dword [ebp-36],2
        je .array_string_flag
        mov esi,array_name_temp
        call strlen_esi
        test eax,eax
        jz .array_flag_ready
        cmp byte [array_name_temp+eax-1],'$'
        jne .array_flag_ready
.array_string_flag:
        mov dl,1
.array_flag_ready:
        mov [array_string+ebx],dl
        jmp .done

.scalar:
        ; AS annotations are removed before name normalization.  AS STRING or
        ; a '$' suffix creates an empty string; all other scalar types start at 0.
        push assignment_name
        push ecx
        push esi
        call normalize_name_span_to
        cmp byte [assignment_name],0
        je .bad
        cmp dword [ebp-36],2
        je .scalar_string
        mov esi,assignment_name
        call strlen_esi
        test eax,eax
        jz .bad
        cmp byte [assignment_name+eax-1],'$'
        je .scalar_string
        mov byte [eval_temp],'0'
        mov byte [eval_temp+1],0
        jmp .set_scalar
.scalar_string:
        mov byte [eval_temp],0
.set_scalar:
        push eval_temp
        push assignment_name
        call set_variable_z
        jmp .done

.bad:
        cmp dword [runtime_error],0
        jne .done
        push msg_bad_dim
        call set_runtime_error_z
        jmp .done
.bad_size:
        push msg_array_size
        call set_runtime_error_z
        jmp .done
.too_many:
        push msg_array_limit
        call set_runtime_error_z
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; strip_dim_type_clause
; Input ESI/ECX = trimmed declaration. Output ECX excludes a top-level AS clause.
; EAX=0 no AS, EAX=1 numeric/other AS type, EAX=2 AS STRING.
strip_dim_type_clause:
        push ebp
        mov ebp,esp
        sub esp,20
        push ebx
        push edx
        push edi
        mov [ebp-4],esi
        mov [ebp-8],ecx
        mov dword [ebp-12],0
        mov [ebp-16],ecx
        xor edi,edi                      ; offset
        xor ebx,ebx                      ; parenthesis depth
        xor edx,edx                      ; quote state
.scan:
        cmp edi,[ebp-8]
        jae .finish
        mov al,[esi+edi]
        cmp al,'"'
        jne .not_quote
        xor edx,1
        inc edi
        jmp .scan
.not_quote:
        test edx,edx
        jnz .next
        cmp al,'('
        jne .not_open
        inc ebx
        jmp .next
.not_open:
        cmp al,')'
        jne .candidate
        test ebx,ebx
        jz .next
        dec ebx
        jmp .next
.candidate:
        test ebx,ebx
        jnz .next
        mov al,[esi+edi]
        or al,20h
        cmp al,'a'
        jne .next
        mov eax,edi
        inc eax
        cmp eax,[ebp-8]
        jae .next
        mov al,[esi+eax]
        or al,20h
        cmp al,'s'
        jne .next

        ; Word boundary before AS.
        test edi,edi
        jz .left_ok
        mov al,[esi+edi-1]
        cmp al,' '
        je .left_ok
        cmp al,9
        jne .next
.left_ok:
        mov eax,edi
        add eax,2
        cmp eax,[ebp-8]
        je .right_ok
        mov al,[esi+eax]
        cmp al,' '
        je .right_ok
        cmp al,9
        jne .next
.right_ok:
        ; Classify the type text after AS.
        mov eax,edi
        add eax,2
        lea esi,[esi+eax]
        mov ecx,[ebp-8]
        sub ecx,eax
        call trim_span
        test ecx,ecx
        jz .malformed
        push type_string
        push ecx
        push esi
        call equals_keyword_span
        test eax,eax
        jz .numeric_type
        mov dword [ebp-12],2
        jmp .truncate
.numeric_type:
        mov dword [ebp-12],1
.truncate:
        mov esi,[ebp-4]
        mov ecx,edi
        call trim_span
        mov [ebp-16],ecx
        jmp .finish
.malformed:
        mov dword [ebp-16],0
        mov dword [ebp-12],1
        jmp .finish
.next:
        inc edi
        mov esi,[ebp-4]
        jmp .scan
.finish:
        mov esi,[ebp-4]
        mov ecx,[ebp-16]
        mov eax,[ebp-12]
        pop edi
        pop edx
        pop ebx
        mov esp,ebp
        pop ebp
        ret

; find_dim_to(pointer,length) -> EAX pointer to top-level TO, or zero.
find_dim_to:
        push ebp
        mov ebp,esp
        push esi
        push edi
        push ebx
        push ecx
        push edx
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        xor edi,edi
        xor ebx,ebx                      ; nested-parenthesis depth
        xor edx,edx                      ; quote state
.scan:
        cmp edi,ecx
        jae .none
        mov al,[esi+edi]
        cmp al,'"'
        jne .not_quote
        xor edx,1
        inc edi
        jmp .scan
.not_quote:
        test edx,edx
        jnz .next
        cmp al,'('
        jne .not_open
        inc ebx
        jmp .next
.not_open:
        cmp al,')'
        jne .candidate
        test ebx,ebx
        jz .next
        dec ebx
        jmp .next
.candidate:
        test ebx,ebx
        jnz .next
        mov al,[esi+edi]
        or al,20h
        cmp al,'t'
        jne .next
        mov eax,edi
        inc eax
        cmp eax,ecx
        jae .next
        mov al,[esi+eax]
        or al,20h
        cmp al,'o'
        jne .next
        test edi,edi
        jz .left_ok
        mov al,[esi+edi-1]
        cmp al,' '
        je .left_ok
        cmp al,9
        jne .next
.left_ok:
        mov eax,edi
        add eax,2
        cmp eax,ecx
        je .found
        mov al,[esi+eax]
        cmp al,' '
        je .found
        cmp al,9
        jne .next
.found:
        lea eax,[esi+edi]
        jmp .done
.next:
        inc edi
        jmp .scan
.none:
        xor eax,eax
.done:
        pop edx
        pop ecx
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 8

; evaluate_dim_integer(pointer,length) -> EAX integer, EDX=1 success/0 failure.
evaluate_dim_integer:
        push ebp
        mov ebp,esp
        sub esp,4
        push esi
        push ecx
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        test ecx,ecx
        jz .bad
        mov dword [eval_work_depth],0
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .failed
        push eval_temp
        call is_integer_text_z
        test eax,eax
        jz .bad
        mov esi,eval_temp
        call atoi_signed
        mov [ebp-4],eax
        mov edx,1
        mov eax,[ebp-4]
        jmp .done
.bad:
        cmp dword [runtime_error],0
        jne .failed
        push msg_array_index_numeric
        call set_runtime_error_z
.failed:
        xor eax,eax
        xor edx,edx
.done:
        pop ecx
        pop esi
        mov esp,ebp
        pop ebp
        ret 8

; is_integer_text_z(z) -> EAX 1/0.  Used for DIM bounds and array indexes.
is_integer_text_z:
        push ebp
        mov ebp,esp
        push esi
        push ebx
        mov esi,[ebp+8]
        xor ebx,ebx
        mov al,[esi]
        cmp al,'+'
        je .sign
        cmp al,'-'
        jne .digits
.sign:
        inc esi
.digits:
        mov al,[esi]
        cmp al,'0'
        jb .no
        cmp al,'9'
        ja .no
.loop:
        mov al,[esi]
        test al,al
        jz .yes
        cmp al,'0'
        jb .no
        cmp al,'9'
        ja .no
        inc esi
        inc ebx
        jmp .loop
.yes:
        mov eax,1
        jmp .done
.no:
        xor eax,eax
.done:
        pop ebx
        pop esi
        mov esp,ebp
        pop ebp
        ret 4

; resolve_array_reference(pointer,length,destination_name)
; Return EAX=0 when the span is not an array reference, EAX=1 on success,
; EAX=2 when it was an array reference but produced a runtime error.
resolve_array_reference:
        push ebp
        mov ebp,esp
        sub esp,96                       ; local normalized base name + locals
        push esi
        push edi
        push ebx
        push ecx
        push edx
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        test ecx,ecx
        jz .not_array
        mov [ebp-24],esi                 ; trimmed reference pointer
        mov [ebp-28],ecx                 ; trimmed reference length

        xor ebx,ebx
.find_open:
        cmp ebx,ecx
        jae .not_array
        cmp byte [esi+ebx],'('
        je .open_found
        inc ebx
        jmp .find_open
.open_found:
        mov [ebp-4],ebx
        cmp ebx,0
        je .not_array
        cmp byte [esi+ecx-1],')'
        jne .not_array

        lea eax,[ebp-96]
        push eax
        push ebx
        push esi
        call normalize_name_span_to
        cmp byte [ebp-96],0
        je .bad_reference

        lea eax,[ebp-96]
        push eax
        call find_array_z
        cmp eax,-1
        je .not_dimensioned
        mov [ebp-8],eax                  ; array metadata index
        mov edx,[array_upper+eax*4]
        mov [ebp-12],edx
        mov edx,[array_lower+eax*4]
        mov [ebp-32],edx
        movzx edx,byte [array_string+eax]
        mov [ebp-16],edx

        ; Evaluate the index expression between '(' and ')'.
        mov esi,[ebp-24]
        mov ecx,[ebp-28]
        mov ebx,[ebp-4]
        lea esi,[esi+ebx+1]
        sub ecx,ebx
        sub ecx,2
        call trim_span
        test ecx,ecx
        jz .bad_reference
        mov dword [eval_work_depth],0
        push eval_temp
        push ecx
        push esi
        call evaluate_atom
        cmp dword [runtime_error],0
        jne .error
        push eval_temp
        call is_numeric_z
        test eax,eax
        jz .bad_index
        push eval_temp
        call is_integer_text_z
        test eax,eax
        jz .bad_index
        mov esi,eval_temp
        call atoi_signed
        cmp eax,[ebp-32]
        jl .out_of_bounds
        cmp eax,[ebp-12]
        jg .out_of_bounds
        mov [ebp-20],eax

        push dword [ebp+16]
        push eax
        lea eax,[ebp-96]
        push eax
        call build_array_element_name
        mov eax,[ebp-16]
        mov [array_last_is_string],eax
        mov eax,1
        jmp .finish

.not_array:
        xor eax,eax
        jmp .finish
.not_dimensioned:
        push msg_array_not_dim
        call set_runtime_error_z
        mov eax,2
        jmp .finish
.bad_index:
        push msg_array_index_numeric
        call set_runtime_error_z
        mov eax,2
        jmp .finish
.out_of_bounds:
        push msg_array_bounds
        call set_runtime_error_z
        mov eax,2
        jmp .finish
.bad_reference:
        push msg_bad_array_reference
        call set_runtime_error_z
.error:
        mov eax,2
.finish:
        pop edx
        pop ecx
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 12

; evaluate_array_bound(pointer,length,destination,mode)
; mode 0=LBOUND, mode 1=UBOUND. Returns output length in EAX.
evaluate_array_bound:
        push ebp
        mov ebp,esp
        push esi
        push edi
        push ebx
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        push array_name_temp
        push ecx
        push esi
        call normalize_name_span_to
        push array_name_temp
        call find_array_z
        cmp eax,-1
        je .missing
        mov ebx,eax
        mov eax,[array_lower+ebx*4]
        cmp dword [ebp+20],0
        je .write
        mov eax,[array_upper+ebx*4]
.write:
        mov edi,[ebp+16]
        call itoa_eax
        mov esi,[ebp+16]
        call strlen_esi
        jmp .done
.missing:
        push msg_array_not_dim
        call set_runtime_error_z
        mov edi,[ebp+16]
        mov byte [edi],0
        xor eax,eax
.done:
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 16

; find_array_z(normalized_name) -> EAX index, or -1.
find_array_z:
        push ebp
        mov ebp,esp
        push esi
        push edi
        push ebx
        xor ebx,ebx
.search:
        cmp ebx,[array_count]
        jae .missing
        mov eax,ebx
        imul eax,VAR_NAME_SIZE
        lea edi,[array_names+eax]
        mov esi,[ebp+8]
        call strings_equal_z
        test eax,eax
        jnz .found
        inc ebx
        jmp .search
.found:
        mov eax,ebx
        jmp .done
.missing:
        mov eax,-1
.done:
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 4

; normalize_name_span_to(pointer,length,destination)
normalize_name_span_to:
        push ebp
        mov ebp,esp
        push esi
        push edi
        push ebx
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        mov edi,[ebp+16]
        call trim_span
        cmp ecx,VAR_NAME_SIZE-1
        jbe .size_ok
        mov ecx,VAR_NAME_SIZE-1
.size_ok:
        xor ebx,ebx
.copy:
        cmp ebx,ecx
        jae .done_copy
        mov al,[esi+ebx]
        cmp al,'a'
        jb .store
        cmp al,'z'
        ja .store
        sub al,20h
.store:
        mov [edi+ebx],al
        inc ebx
        jmp .copy
.done_copy:
        mov byte [edi+ebx],0
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 12

; build_array_element_name(base_z,index,destination)
build_array_element_name:
        push ebp
        mov ebp,esp
        push esi
        push edi
        push ebx
        mov esi,[ebp+8]
        mov edi,[ebp+16]
        mov ebx,VAR_NAME_SIZE-16
.copy_base:
        test ebx,ebx
        jz .append
        mov al,[esi]
        test al,al
        jz .append
        mov [edi],al
        inc esi
        inc edi
        dec ebx
        jmp .copy_base
.append:
        mov byte [edi],'('
        inc edi
        mov eax,[ebp+12]
        call itoa_eax                     ; signed lower bounds are supported
        mov byte [edi],')'
        mov byte [edi+1],0
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 12

; ----------------------------------------------------------------------------
; CLEAR / CLR (v0.1.13)
; ----------------------------------------------------------------------------
; Reset scalar values to their BASIC defaults while retaining symbol names.
; Numeric variables become "0"; string variables become empty. Arrays are
; deallocated, and READ restarts at the first DATA item.
clear_runtime_variables:
        pushad
        mov byte [exec_output_buffer],0
        mov dword [exec_output_length],0
        mov dword [exec_output_truncated],0
        xor ebx,ebx
.clear_scalar_loop:
        cmp ebx,[variable_count]
        jae .clear_arrays
        mov eax,ebx
        imul eax,VAR_NAME_SIZE
        lea esi,[variable_names+eax]
        mov edi,esi
.find_name_end:
        cmp byte [edi],0
        je .name_end
        inc edi
        jmp .find_name_end
.name_end:
        cmp edi,esi
        je .numeric_default
        cmp byte [edi-1],'$'
        je .string_default
.numeric_default:
        mov eax,ebx
        imul eax,VAR_VALUE_SIZE
        lea edi,[variable_values+eax]
        mov byte [edi],'0'
        mov byte [edi+1],0
        jmp .next_scalar
.string_default:
        mov eax,ebx
        imul eax,VAR_VALUE_SIZE
        lea edi,[variable_values+eax]
        mov byte [edi],0
.next_scalar:
        inc ebx
        jmp .clear_scalar_loop

.clear_arrays:
        mov dword [array_count],0
        mov dword [array_last_is_string],0
        mov dword [data_read_index],0
        popad
        ret

; ----------------------------------------------------------------------------
; Symbol table
; ----------------------------------------------------------------------------

; set_variable_z(name,value)
set_variable_z:
        push ebp
        mov ebp,esp
        pushad
        mov esi,[ebp+8]
        mov edi,var_build_name
        mov ecx,VAR_NAME_SIZE-1
.normalize:
        mov al,[esi]
        test al,al
        jz .normalized
        cmp al,'a'
        jb .store_name
        cmp al,'z'
        ja .store_name
        sub al,20h
.store_name:
        stosb
        inc esi
        dec ecx
        jnz .normalize
.normalized:
        mov byte [edi],0

        ; EXEC_OUTPUT$ has dedicated 1 MiB storage. Keep the ordinary scalar
        ; table unchanged at VAR_VALUE_SIZE bytes per variable.
        mov esi,var_build_name
        mov edi,var_exec_output
        call strings_equal_z
        test eax,eax
        jz .ordinary_variable
        mov esi,[ebp+12]
        mov edi,exec_output_buffer
        call copy_z_limited_exec_output
        jmp .done

.ordinary_variable:
        xor ebx,ebx
.search:
        cmp ebx,[variable_count]
        jae .new
        mov eax,ebx
        imul eax,VAR_NAME_SIZE
        lea edi,[variable_names+eax]
        mov esi,var_build_name
        call strings_equal_z
        test eax,eax
        jnz .found
        inc ebx
        jmp .search
.new:
        cmp ebx,MAX_VARIABLES
        jae .done
        inc [variable_count]
        mov eax,ebx
        imul eax,VAR_NAME_SIZE
        lea edi,[variable_names+eax]
        mov esi,var_build_name
        call copy_z_limited_name
.found:
        mov eax,ebx
        imul eax,VAR_VALUE_SIZE
        lea edi,[variable_values+eax]
        mov esi,[ebp+12]
        call copy_z_limited_value
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; get_variable_z(name), returns pointer in EAX or zero.
get_variable_z:
        push ebp
        mov ebp,esp
        push esi
        push edi
        push ebx
        mov esi,[ebp+8]
        mov edi,var_build_name
        mov ecx,VAR_NAME_SIZE-1
.normalize:
        mov al,[esi]
        test al,al
        jz .normalized
        cmp al,'a'
        jb .store
        cmp al,'z'
        ja .store
        sub al,20h
.store:
        stosb
        inc esi
        dec ecx
        jnz .normalize
.normalized:
        mov byte [edi],0

        ; Return the dedicated large value without consuming a scalar-table slot.
        mov esi,var_build_name
        mov edi,var_exec_output
        call strings_equal_z
        test eax,eax
        jz .ordinary_variable
        mov eax,exec_output_buffer
        jmp .done

.ordinary_variable:
        xor ebx,ebx
.search:
        cmp ebx,[variable_count]
        jae .not_found
        mov eax,ebx
        imul eax,VAR_NAME_SIZE
        lea edi,[variable_names+eax]
        mov esi,var_build_name
        call strings_equal_z
        test eax,eax
        jnz .found
        inc ebx
        jmp .search
.found:
        mov eax,ebx
        imul eax,VAR_VALUE_SIZE
        add eax,variable_values
        jmp .done
.not_found:
        xor eax,eax
.done:
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 4

; ----------------------------------------------------------------------------
; Output and HTTP response
; ----------------------------------------------------------------------------

; output_append_span(pointer,length)
output_append_span:
        push ebp
        mov ebp,esp
        pushad
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        mov eax,[output_length]
        cmp eax,MAX_OUTPUT
        jae .truncated
        mov edx,MAX_OUTPUT
        sub edx,eax
        cmp ecx,edx
        jbe .length_ok
        mov ecx,edx
        mov [output_truncated],1
.length_ok:
        mov edi,[output_buffer]
        add edi,eax
        add [output_length],ecx
        rep movsb
        mov byte [edi],0
        jmp .done
.truncated:
        mov [output_truncated],1
.done:
        popad
        mov esp,ebp
        pop ebp
        ret 8

; Direct/local execution writes only the BASIC output, without CGI headers.
write_direct_response:
        cmp dword [runtime_error],0
        jne .direct_error
        cmp dword [output_truncated],0
        jne .direct_truncated
        push dword [output_length]
        push dword [output_buffer]
        call raw_stdout_write
        ret
.direct_error:
        mov esi,runtime_error_message
        call strlen_esi
        push eax
        push runtime_error_message
        call raw_stdout_write
        push crlf_len
        push crlf
        call raw_stdout_write
        ret
.direct_truncated:
        push msg_output_large_len
        push msg_output_large
        call raw_stdout_write
        push crlf_len
        push crlf
        call raw_stdout_write
        ret

write_http_response:
        cmp [runtime_error],0
        jne .error
        cmp [output_truncated],0
        jne .truncated

        ; Optional CGI Status header. A normal 200 response omits it.
        cmp dword [response_status_code],200
        je .content_type
        push dword [response_status_line_length]
        push response_status_line
        call raw_stdout_write

.content_type:
        push header_content_type_prefix_len
        push header_content_type_prefix
        call raw_stdout_write
        mov esi,response_content_type
        call strlen_esi
        push eax
        push response_content_type
        call raw_stdout_write
        push crlf_len
        push crlf
        call raw_stdout_write

        push header_fixed_len
        push header_fixed
        call raw_stdout_write

        cmp dword [response_custom_headers_length],0
        je .headers_done
        push dword [response_custom_headers_length]
        push response_custom_headers
        call raw_stdout_write
.headers_done:
        push crlf_len
        push crlf
        call raw_stdout_write

        push dword [output_length]
        push dword [output_buffer]
        call raw_stdout_write
        ret

.error:
        push header_error_len
        push header_error
        call raw_stdout_write
        mov esi,runtime_error_message
        call strlen_esi
        push eax
        push runtime_error_message
        call raw_stdout_write
        ret

.truncated:
        push header_error_len
        push header_error
        call raw_stdout_write
        push msg_output_large_len
        push msg_output_large
        call raw_stdout_write
        ret

; raw_stdout_write(pointer,length)
raw_stdout_write:
        push ebp
        mov ebp,esp
        push 0
        push bytes_done
        push dword [ebp+12]
        push dword [ebp+8]
        push STD_OUTPUT_HANDLE
        call [GetStdHandle]
        push eax
        call [WriteFile]
        mov esp,ebp
        pop ebp
        ret 8

set_runtime_error_z:
        push ebp
        mov ebp,esp
        pushad
        mov [runtime_error],1
        mov esi,[ebp+8]
        mov edi,runtime_error_message
        mov ecx,1023
.copy_message:
        test ecx,ecx
        jz .terminate
        mov al,[esi]
        test al,al
        jz .append_statement
        stosb
        inc esi
        dec ecx
        jmp .copy_message
.append_statement:
        mov eax,[current_statement_len]
        test eax,eax
        jz .terminate
        mov esi,error_statement_prefix
.copy_prefix:
        test ecx,ecx
        jz .terminate
        mov al,[esi]
        test al,al
        jz .copy_statement
        stosb
        inc esi
        dec ecx
        jmp .copy_prefix
.copy_statement:
        mov esi,[current_statement_ptr]
        mov eax,[current_statement_len]
        cmp eax,240
        jbe .statement_length_ok
        mov eax,240
.statement_length_ok:
        cmp eax,ecx
        jbe .copy_span
        mov eax,ecx
.copy_span:
        mov ecx,eax
        rep movsb
.terminate:
        mov byte [edi],0
        popad
        mov esp,ebp
        pop ebp
        ret 4

; ----------------------------------------------------------------------------
; String and parsing utilities
; ----------------------------------------------------------------------------

trim_span:
        ; ESI pointer, ECX length -> trimmed ESI/ECX.
.left:
        test ecx,ecx
        jz .done
        mov al,[esi]
        cmp al,' '
        je .left_inc
        cmp al,9
        jne .right
.left_inc:
        inc esi
        dec ecx
        jmp .left
.right:
        test ecx,ecx
        jz .done
        mov al,[esi+ecx-1]
        cmp al,' '
        je .right_dec
        cmp al,9
        je .right_dec
        cmp al,13
        je .right_dec
        cmp al,10
        jne .done
.right_dec:
        dec ecx
        jmp .right
.done:
        ret

skip_spaces_esi:
.loop:
        mov al,[esi]
        cmp al,' '
        je .inc
        cmp al,9
        jne .done
.inc:
        inc esi
        jmp .loop
.done:
        ret

strlen_esi:
        push edi
        mov edi,esi
        xor eax,eax
.loop:
        cmp byte [edi],0
        je .done
        inc edi
        inc eax
        jmp .loop
.done:
        pop edi
        ret

strings_equal_z:
        ; ESI,EDI -> EAX boolean, case-insensitive.
.loop:
        mov al,[esi]
        mov ah,[edi]
        cmp al,'a'
        jb .a_ok
        cmp al,'z'
        ja .a_ok
        sub al,20h
.a_ok:
        cmp ah,'a'
        jb .b_ok
        cmp ah,'z'
        ja .b_ok
        sub ah,20h
.b_ok:
        cmp al,ah
        jne .no
        test al,al
        jz .yes
        inc esi
        inc edi
        jmp .loop
.yes:
        mov eax,1
        ret
.no:
        xor eax,eax
        ret

starts_with_i:
        ; ESI=text, EDI=prefix -> EAX boolean.
.loop:
        mov al,[edi]
        test al,al
        jz .yes
        mov ah,[esi]
        test ah,ah
        jz .no
        cmp al,'a'
        jb .a_ok
        cmp al,'z'
        ja .a_ok
        sub al,20h
.a_ok:
        cmp ah,'a'
        jb .b_ok
        cmp ah,'z'
        ja .b_ok
        sub ah,20h
.b_ok:
        cmp al,ah
        jne .no
        inc esi
        inc edi
        jmp .loop
.yes:
        mov eax,1
        ret
.no:
        xor eax,eax
        ret

; starts_keyword_span(pointer,length,keyword-z) returns keyword length or zero.
starts_keyword_span:
        push ebp
        mov ebp,esp
        push esi
        push edi
        push ebx
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        mov edi,[ebp+16]
        xor ebx,ebx
.loop:
        mov al,[edi+ebx]
        test al,al
        jz .boundary
        cmp ebx,ecx
        jae .no
        mov ah,[esi+ebx]
        call compare_chars_i
        jne .no
        inc ebx
        jmp .loop
.boundary:
        cmp ebx,ecx
        je .yes
        mov al,[esi+ebx]
        cmp al,' '
        je .yes
        cmp al,9
        je .yes
        cmp al,'('
        je .yes
        jmp .no
.yes:
        mov eax,ebx
        jmp .done
.no:
        xor eax,eax
.done:
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 12

; equals_keyword_span(pointer,length,keyword-z), returns boolean.
equals_keyword_span:
        push ebp
        mov ebp,esp
        push esi
        push ecx
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        push dword [ebp+16]
        push ecx
        push esi
        call starts_keyword_span
        test eax,eax
        jz .no
        cmp eax,ecx
        jne .no
        mov eax,1
        jmp .done
.no:
        xor eax,eax
.done:
        pop ecx
        pop esi
        mov esp,ebp
        pop ebp
        ret 12

; starts_function_span(pointer,length,name-z), returns boolean.
starts_function_span:
        push ebp
        mov ebp,esp
        push esi
        push edi
        push ecx
        push edx
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        mov edi,[ebp+16]
        xor edx,edx
.loop:
        mov al,[edi+edx]
        test al,al
        jz .open
        cmp edx,ecx
        jae .no
        mov ah,[esi+edx]
        call compare_chars_i
        jne .no
        inc edx
        jmp .loop
.open:
        cmp edx,ecx
        jae .no
        cmp byte [esi+edx],'('
        jne .no
        mov eax,1
        jmp .done
.no:
        xor eax,eax
.done:
        pop edx
        pop ecx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 12

compare_chars_i:
        ; AL and AH. Flags from CMP.
        cmp al,'a'
        jb .a_ok
        cmp al,'z'
        ja .a_ok
        sub al,20h
.a_ok:
        cmp ah,'a'
        jb .b_ok
        cmp ah,'z'
        ja .b_ok
        sub ah,20h
.b_ok:
        cmp al,ah
        ret

; find_assignment_equal(pointer,length), returns pointer or zero.
find_assignment_equal:
        push ebp
        mov ebp,esp
        push esi
        push ecx
        push edx
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        xor edx,edx
.loop:
        test ecx,ecx
        jz .none
        mov al,[esi]
        cmp al,'"'
        jne .check
        xor edx,1
        jmp .next
.check:
        test edx,edx
        jnz .next
        cmp al,'='
        je .found
.next:
        inc esi
        dec ecx
        jmp .loop
.found:
        mov eax,esi
        jmp .done
.none:
        xor eax,eax
.done:
        pop edx
        pop ecx
        pop esi
        mov esp,ebp
        pop ebp
        ret 8

; find_keyword_outside(pointer,length,keyword-z), returns pointer or zero.
find_keyword_outside:
        push ebp
        mov ebp,esp
        push esi
        push edi
        push ebx
        push ecx
        push edx
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        mov edi,[ebp+16]
        ; EBX is the quote-state flag. match_word_at uses EDX internally, so
        ; EDX cannot safely carry state across candidate matches. The old code
        ; made a partial keyword prefix (for example the leading T in TRUE
        ; while searching for THEN) look like an open quote and skipped the
        ; real keyword later on the line.
        xor ebx,ebx
.scan:
        test ecx,ecx
        jz .none
        mov al,[esi]
        cmp al,'"'
        jne .not_quote
        xor ebx,1
        jmp .advance
.not_quote:
        test ebx,ebx
        jnz .advance
        push ecx
        push esi
        push edi
        call match_word_at
        test eax,eax
        jnz .found
.advance:
        inc esi
        dec ecx
        jmp .scan
.found:
        mov eax,esi
        jmp .done
.none:
        xor eax,eax
.done:
        pop edx
        pop ecx
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 12

; match_word_at(keyword, pointer, available_length) -- internal call order above.
match_word_at:
        push ebp
        mov ebp,esp
        push esi
        push edi
        mov edi,[ebp+8]
        mov esi,[ebp+12]
        mov ecx,[ebp+16]
        xor edx,edx
.loop:
        mov al,[edi+edx]
        test al,al
        jz .boundary
        cmp edx,ecx
        jae .no
        mov ah,[esi+edx]
        call compare_chars_i
        jne .no
        inc edx
        jmp .loop
.boundary:
        ; Require word boundary on both sides where applicable.
        cmp edx,ecx
        je .yes
        mov al,[esi+edx]
        cmp al,' '
        je .yes
        cmp al,9
        je .yes
        cmp al,13
        je .yes
        cmp al,10
        je .yes
        cmp al,':'
        je .yes
.no:
        xor eax,eax
        jmp .done
.yes:
        mov eax,1
.done:
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 12

; find_token_outside(pointer,length,token-z), returns pointer or zero.
find_token_outside:
        push ebp
        mov ebp,esp
        push esi
        push edi
        push ebx
        push ecx
        push edx
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        mov edi,[ebp+16]
        xor ebx,ebx
.scan:
        test ecx,ecx
        jz .none
        mov al,[esi]
        cmp al,'"'
        jne .check
        xor ebx,1
        jmp .advance
.check:
        test ebx,ebx
        jnz .advance
        push ecx
        push esi
        push edi
        call match_token_at
        test eax,eax
        jnz .found
.advance:
        inc esi
        dec ecx
        jmp .scan
.found:
        mov eax,esi
        jmp .done
.none:
        xor eax,eax
.done:
        pop edx
        pop ecx
        pop ebx
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 12

match_token_at:
        push ebp
        mov ebp,esp
        push esi
        push edi
        mov edi,[ebp+8]
        mov esi,[ebp+12]
        mov ecx,[ebp+16]
        xor edx,edx
.loop:
        mov al,[edi+edx]
        test al,al
        jz .yes
        cmp edx,ecx
        jae .no
        cmp al,[esi+edx]
        jne .no
        inc edx
        jmp .loop
.yes:
        mov eax,1
        jmp .done
.no:
        xor eax,eax
.done:
        pop edi
        pop esi
        mov esp,ebp
        pop ebp
        ret 12

copy_trimmed_name:
        push ebp
        mov ebp,esp
        mov esi,[ebp+8]
        mov ecx,[ebp+12]
        call trim_span
        mov edi,var_build_name
        cmp ecx,VAR_NAME_SIZE-1
        jbe .size
        mov ecx,VAR_NAME_SIZE-1
.size:
        rep movsb
        mov byte [edi],0
        mov esp,ebp
        pop ebp
        ret 8

copy_span_to_name:
        push ebp
        mov ebp,esp
        mov ecx,[ebp+8]
        mov esi,[ebp+12]
        call trim_span
        mov edi,var_build_name
        cmp ecx,VAR_NAME_SIZE-1
        jbe .copy
        mov ecx,VAR_NAME_SIZE-1
.copy:
        rep movsb
        mov byte [edi],0
        mov esp,ebp
        pop ebp
        ret 8

is_identifier_start:
        ; AL -> EAX boolean.
        cmp al,'A'
        jb .lower
        cmp al,'Z'
        jbe .yes
.lower:
        cmp al,'a'
        jb .underscore
        cmp al,'z'
        jbe .yes
.underscore:
        cmp al,'_'
        je .yes
        xor eax,eax
        ret
.yes:
        mov eax,1
        ret

truthy_z:
        cmp byte [esi],0
        je .no
        push esi
        call is_numeric_z
        test eax,eax
        jz .text_yes
        call parse_decimal_to_fpu
        test eax,eax
        jz .text_yes
        fstp st0
        cmp dword [fpu_scaled_input],0
        jne .yes
.no:
        xor eax,eax
        ret
.text_yes:
.yes:
        mov eax,1
        ret

; VAL-compatible signed decimal prefix parser.
; Input: ESI -> zero-terminated text. Output: EAX signed 32-bit integer.
; Leading spaces/tabs and an optional sign are accepted. Parsing stops at
; the first non-digit; a string without digits returns zero.
val_integer_z:
        push ebx
        push ecx
        push edx
        xor eax,eax
        xor ebx,ebx                    ; 1 means negative
.skip_space:
        mov dl,[esi]
        cmp dl,' '
        je .space_advance
        cmp dl,9
        jne .sign
.space_advance:
        inc esi
        jmp .skip_space
.sign:
        cmp byte [esi],'-'
        jne .plus
        mov bl,1
        inc esi
        jmp .digits
.plus:
        cmp byte [esi],'+'
        jne .digits
        inc esi
.digits:
        xor ecx,ecx
.loop:
        mov dl,[esi]
        cmp dl,'0'
        jb .finish
        cmp dl,'9'
        ja .finish
        imul eax,10
        sub dl,'0'
        movzx edx,dl
        add eax,edx
        inc esi
        inc ecx
        jmp .loop
.finish:
        test ecx,ecx
        jz .zero
        test bl,bl
        jz .done
        neg eax
        jmp .done
.zero:
        xor eax,eax
.done:
        pop edx
        pop ecx
        pop ebx
        ret

atoi_unsigned:
        xor eax,eax
.loop:
        mov dl,[esi]
        cmp dl,'0'
        jb .done
        cmp dl,'9'
        ja .done
        imul eax,10
        sub dl,'0'
        movzx edx,dl
        add eax,edx
        inc esi
        jmp .loop
.done:
        ret


; ----------------------------------------------------------------------------
; Decimal/x87 helpers (v0.1.31)
; ----------------------------------------------------------------------------

; parse_decimal_to_fpu
; Input: ESI -> zero-terminated signed decimal text.
; Accepts up to six fractional digits and ignores further fractional digits.
; Output: EAX=1 and ST0=value, or EAX=0 with an empty x87 stack.
parse_decimal_to_fpu:
        push ebx
        push ecx
        push edx
        push edi
        finit
        xor ebx,ebx                    ; sign flag
        xor edi,edi                    ; whole part
        xor ecx,ecx                    ; digit-seen flag
.pd_skip:
        mov al,[esi]
        cmp al,' '
        je .pd_skip_one
        cmp al,9
        jne .pd_sign
.pd_skip_one:
        inc esi
        jmp .pd_skip
.pd_sign:
        cmp byte [esi],'-'
        jne .pd_plus
        mov ebx,1
        inc esi
        jmp .pd_whole
.pd_plus:
        cmp byte [esi],'+'
        jne .pd_whole
        inc esi
.pd_whole:
        mov al,[esi]
        cmp al,'0'
        jb .pd_fraction_start
        cmp al,'9'
        ja .pd_fraction_start
        mov ecx,1
        imul edi,edi,10
        jo .pd_bad
        movzx eax,al
        sub eax,'0'
        add edi,eax
        jo .pd_bad
        cmp edi,2147                  ; micro-unit conversion must fit dword
        ja .pd_bad
        inc esi
        jmp .pd_whole
.pd_fraction_start:
        xor edx,edx                    ; fraction value
        mov dword [fpu_fraction_digits],0
        cmp byte [esi],'.'
        jne .pd_finish_parse
        inc esi
.pd_fraction:
        mov al,[esi]
        cmp al,'0'
        jb .pd_pad
        cmp al,'9'
        ja .pd_pad
        mov ecx,1
        cmp dword [fpu_fraction_digits],6
        jae .pd_skip_extra
        imul edx,edx,10
        movzx eax,al
        sub eax,'0'
        add edx,eax
        inc dword [fpu_fraction_digits]
.pd_skip_extra:
        inc esi
        jmp .pd_fraction
.pd_pad:
        cmp dword [fpu_fraction_digits],6
        jae .pd_finish_parse
        imul edx,edx,10
        inc dword [fpu_fraction_digits]
        jmp .pd_pad
.pd_finish_parse:
        test ecx,ecx
        jz .pd_bad
        mov eax,edi
        imul eax,1000000
        jo .pd_bad
        add eax,edx
        jo .pd_bad
        test ebx,ebx
        jz .pd_store
        neg eax
.pd_store:
        mov [fpu_scaled_input],eax
        fild dword [fpu_scaled_input]
        fild dword [const_million]
        fdivp st1,st0
        mov eax,1
        jmp .pd_done
.pd_bad:
        finit
        xor eax,eax
.pd_done:
        pop edi
        pop edx
        pop ecx
        pop ebx
        ret

; format_fpu_decimal6
; Input: ST0=result, EDI=destination. Returns EAX=string length.
; Rounds to six decimals and removes trailing zeroes and a trailing decimal dot.
format_fpu_decimal6:
        push ebx
        push ecx
        push edx
        push esi
        mov esi,edi
        fild dword [const_million]
        fmulp st1,st0
        fistp dword [fpu_scaled_output]
        mov eax,[fpu_scaled_output]
        cmp eax,80000000h
        jne .ffd_value_ok
        push msg_real_range
        call set_runtime_error_z
        mov byte [edi],0
        xor eax,eax
        jmp .ffd_done
.ffd_value_ok:
        test eax,eax
        jns .ffd_positive
        mov byte [edi],'-'
        inc edi
        neg eax
.ffd_positive:
        xor edx,edx
        mov ebx,1000000
        div ebx
        mov [fpu_fraction_value],edx
        call utoa_eax
        mov edx,[fpu_fraction_value]
        test edx,edx
        jz .ffd_finish
        mov byte [edi],'.'
        inc edi
        mov eax,edx
        call six_decimal_digits
        mov byte [edi],0
.ffd_trim:
        cmp edi,esi
        jbe .ffd_finish
        cmp byte [edi-1],'0'
        jne .ffd_finish
        dec edi
        mov byte [edi],0
        jmp .ffd_trim
.ffd_finish:
        cmp edi,esi
        jbe .ffd_length
        cmp byte [edi-1],'.'
        jne .ffd_length
        dec edi
        mov byte [edi],0
.ffd_length:
        mov eax,edi
        sub eax,esi
.ffd_done:
        pop esi
        pop edx
        pop ecx
        pop ebx
        ret

atoi_signed:
        push ebx
        xor ebx,ebx
        cmp byte [esi],'-'
        jne .positive
        mov bl,1
        inc esi
.positive:
        call atoi_unsigned
        test bl,bl
        jz .done
        neg eax
.done:
        pop ebx
        ret

; Integer square root. Input EAX must be non-negative; output is
; floor(sqrt(EAX)). Newton iteration avoids multiplication overflow.
isqrt_eax:
        push ebx
        push ecx
        push edx
        mov ebx,eax
        cmp eax,1
        jbe .done_small
        mov ecx,eax
        shr ecx,1
        inc ecx
.iterate:
        mov eax,ebx
        xor edx,edx
        div ecx
        add eax,ecx
        shr eax,1
        cmp eax,ecx
        jae .finished
        mov ecx,eax
        jmp .iterate
.finished:
        mov eax,ecx
.done_small:
        pop edx
        pop ecx
        pop ebx
        ret

utoa_eax:
        ; EAX unsigned, EDI destination. Returns EDI after terminating zero.
        push ebx
        push ecx
        push edx
        xor ecx,ecx
        mov ebx,10
        test eax,eax
        jnz .convert
        mov byte [edi],'0'
        inc edi
        jmp .terminate
.convert:
        xor edx,edx
        div ebx
        add dl,'0'
        push edx
        inc ecx
        test eax,eax
        jnz .convert
.write:
        pop edx
        mov [edi],dl
        inc edi
        loop .write
.terminate:
        mov byte [edi],0
        pop edx
        pop ecx
        pop ebx
        ret

; EAX unsigned 32-bit value, EBX base, ESI digit table, EDI destination.
; The destination is zero-terminated and EDI is left at the terminator.
utoa_base_eax:
        push ecx
        push edx
        xor ecx,ecx
        test eax,eax
        jnz .convert
        mov byte [edi],'0'
        inc edi
        jmp .terminate
.convert:
        xor edx,edx
        div ebx
        push edx
        inc ecx
        test eax,eax
        jnz .convert
.write:
        pop edx
        mov dl,[esi+edx]
        mov [edi],dl
        inc edi
        loop .write
.terminate:
        mov byte [edi],0
        pop edx
        pop ecx
        ret

utoa_hex_eax:
        push ebx
        push esi
        mov ebx,16
        mov esi,digits_upper
        call utoa_base_eax
        pop esi
        pop ebx
        ret

utoa_oct_eax:
        push ebx
        push esi
        mov ebx,8
        mov esi,digits_upper
        call utoa_base_eax
        pop esi
        pop ebx
        ret

two_digits:
        ; EAX 0..99, EDI destination, no terminator.
        xor edx,edx
        mov ecx,10
        div ecx
        add al,'0'
        add dl,'0'
        mov [edi],al
        mov [edi+1],dl
        ret

four_digits:
        ; EAX 0..9999, EDI destination.
        push ebx
        push edx
        mov ebx,1000
        xor edx,edx
        div ebx
        add al,'0'
        mov [edi],al
        mov eax,edx
        mov ebx,100
        xor edx,edx
        div ebx
        add al,'0'
        mov [edi+1],al
        mov eax,edx
        mov ebx,10
        xor edx,edx
        div ebx
        add al,'0'
        add dl,'0'
        mov [edi+2],al
        mov [edi+3],dl
        pop edx
        pop ebx
        ret

html_encode_z:
        xor eax,eax
.loop:
        mov dl,[esi]
        test dl,dl
        jz .done
        cmp dl,'&'
        je .amp
        cmp dl,'<'
        je .lt
        cmp dl,'>'
        je .gt
        cmp dl,'"'
        je .quot
        cmp dl,39
        je .apos
        cmp eax,EVAL_SIZE-2
        jae .done
        mov [edi],dl
        inc edi
        inc eax
        inc esi
        jmp .loop
.amp:
        push ent_amp_len
        push ent_amp
        jmp .entity
.lt:
        push ent_lt_len
        push ent_lt
        jmp .entity
.gt:
        push ent_gt_len
        push ent_gt
        jmp .entity
.quot:
        push ent_quot_len
        push ent_quot
        jmp .entity
.apos:
        push ent_apos_len
        push ent_apos
.entity:
        pop ebx
        pop ecx
        mov edx,EVAL_SIZE-1
        sub edx,eax
        cmp ecx,edx
        ja .done
        push ecx
        push esi
        mov esi,ebx
        rep movsb
        pop esi
        pop ecx
        add eax,ecx
        inc esi
        jmp .loop
.done:
        mov byte [edi],0
        ret

json_encode_z:
        xor eax,eax
.loop:
        mov dl,[esi]
        test dl,dl
        jz .done
        cmp dl,'"'
        je .quote
        cmp dl,'\'
        je .slash
        cmp dl,13
        je .cr
        cmp dl,10
        je .lf
        cmp dl,9
        je .tab
        cmp eax,EVAL_SIZE-2
        jae .done
        mov [edi],dl
        inc edi
        inc eax
        inc esi
        jmp .loop
.quote:
        mov dh,'"'
        jmp .escape
.slash:
        mov dh,'\'
        jmp .escape
.cr:
        mov dh,'r'
        jmp .escape
.lf:
        mov dh,'n'
        jmp .escape
.tab:
        mov dh,'t'
.escape:
        cmp eax,EVAL_SIZE-3
        jae .done
        mov byte [edi],'\'
        mov [edi+1],dh
        add edi,2
        add eax,2
        inc esi
        jmp .loop
.done:
        mov byte [edi],0
        ret

copy_z_limited_exec_output:
        mov ecx,EXEC_OUTPUT_SIZE-1
.loop:
        mov al,[esi]
        test al,al
        jz .finish
        mov [edi],al
        inc esi
        inc edi
        dec ecx
        jnz .loop
.finish:
        mov byte [edi],0
        ret

copy_z_limited_eval:
        mov ecx,EVAL_SIZE-1
        jmp copy_z_limited_common
copy_z_limited_name:
        mov ecx,VAR_NAME_SIZE-1
        jmp copy_z_limited_common
copy_z_limited_value:
        mov ecx,VAR_VALUE_SIZE-1
copy_z_limited_common:
.loop:
        mov al,[esi]
        stosb
        inc esi
        test al,al
        jz .done
        loop .loop
        mov byte [edi-1],0
.done:
        ret

copy_z_advance:
        ; EBX source, EDI destination. Copies including zero, then leaves EDI
        ; positioned over the copied zero so another string can overwrite it.
.loop:
        mov al,[ebx]
        mov [edi],al
        inc ebx
        test al,al
        jz .done
        inc edi
        jmp .loop
.done:
        ret

copy_z_advance_nozero:
.loop:
        mov al,[ebx]
        test al,al
        jz .done
        mov [edi],al
        inc ebx
        inc edi
        jmp .loop
.done:
        ret

; ----------------------------------------------------------------------------
; Read-only data
; ----------------------------------------------------------------------------

section '.data' data readable writeable

default_content_type db 'text/html; charset=utf-8',0
default_content_type_len = $-default_content_type-1

header_content_type_prefix db 'Content-Type: '
header_content_type_prefix_len = $-header_content_type_prefix

header_fixed db 'X-Content-Type-Options: nosniff',13,10
             db 'X-ApacheBAS-Engine: FASM-v0.1.34.3',13,10
header_fixed_len = $-header_fixed

status_header_prefix db 'Status: '
status_header_prefix_len = $-status_header_prefix
status_reason_ok db 'OK',0
status_reason_created db 'Created',0
status_reason_no_content db 'No Content',0
status_reason_moved db 'Moved Permanently',0
status_reason_found db 'Found',0
status_reason_bad_request db 'Bad Request',0
status_reason_unauthorized db 'Unauthorized',0
status_reason_forbidden db 'Forbidden',0
status_reason_not_found db 'Not Found',0
status_reason_conflict db 'Conflict',0
status_reason_unprocessable db 'Unprocessable Entity',0
status_reason_too_many db 'Too Many Requests',0
status_reason_internal db 'Internal Server Error',0
status_reason_unavailable db 'Service Unavailable',0
status_reason_custom db 'Custom Status',0

directive_status_prefix db '@@STATUS ',0
directive_status_prefix_len = $-directive_status_prefix-1
directive_content_type_prefix db '@@CONTENT-TYPE ',0
directive_content_type_prefix_len = $-directive_content_type_prefix-1
directive_header_prefix db '@@HEADER ',0
directive_header_prefix_len = $-directive_header_prefix-1

header_error db 'Status: 500 Internal Server Error',13,10
             db 'Content-Type: text/plain; charset=utf-8',13,10
             db 'X-Content-Type-Options: nosniff',13,10
             db 'X-ApacheBAS-Engine: FASM-v0.1.34.3',13,10,13,10
header_error_len = $-header_error

error_statement_prefix db 13,10,'Statement: ',0

msg_fatal_alloc db 'Status: 500 Internal Server Error',13,10,'Content-Type: text/plain',13,10,13,10,'ApacheBAS-ASM: memory allocation failed.'
msg_fatal_alloc_len = $-msg_fatal_alloc
msg_no_script db 'ApacheBAS-ASM: Apache did not supply PATH_TRANSLATED or SCRIPT_FILENAME.',0
msg_bad_extension db 'ApacheBAS-ASM executes only .bas files.',0
msg_script_open db 'ApacheBAS-ASM could not open the requested BASIC script.',0
msg_script_size db 'ApacheBAS-ASM could not determine the BASIC script size.',0
msg_script_read db 'ApacheBAS-ASM could not read the BASIC script.',0
msg_script_large db 'ApacheBAS-ASM: script exceeds the 4 MiB limit.',0
msg_unclosed_template db 'ApacheBAS-ASM: unclosed BASIC template block.',0
msg_unsupported db 'ApacheBAS-ASM v0.1.34.3: unsupported BASIC statement.',0
msg_directive_large db 'ApacheBAS-ASM v0.1.34.3: response directive is too long.',0
msg_bad_status_directive db 'ApacheBAS-ASM v0.1.34.3: invalid @@STATUS directive.',0
msg_bad_content_type_directive db 'ApacheBAS-ASM v0.1.34.3: invalid @@CONTENT-TYPE directive.',0
msg_content_type_large db 'ApacheBAS-ASM v0.1.34.3: content type is too long.',0
msg_bad_header_directive db 'ApacheBAS-ASM v0.1.34.3: invalid @@HEADER directive.',0
msg_headers_large db 'ApacheBAS-ASM v0.1.34.3: custom response headers exceed 8 KiB.',0
msg_bad_if db 'ApacheBAS-ASM v0.1.34.3: IF requires THEN on the same line.',0
msg_bad_for db 'ApacheBAS-ASM v0.1.34.3: malformed FOR statement.',0
msg_missing_next db 'ApacheBAS-ASM v0.1.34.3: FOR without matching NEXT.',0
msg_unmatched_next db 'ApacheBAS-ASM v0.1.34.3: NEXT without matching FOR.',0
msg_zero_step db 'ApacheBAS-ASM v0.1.34.3: FOR STEP cannot be zero.',0
msg_for_depth db 'ApacheBAS-ASM v0.1.34.3: FOR nesting limit exceeded.',0
msg_for_limit db 'ApacheBAS-ASM v0.1.34.3: FOR iteration limit exceeded.',0
msg_bad_while db 'ApacheBAS-ASM v0.1.34.3: WHILE requires a condition.',0
msg_missing_wend db 'ApacheBAS-ASM v0.1.34.3: WHILE without matching WEND.',0
msg_unmatched_wend db 'ApacheBAS-ASM v0.1.34.3: WEND without matching WHILE.',0
msg_while_depth db 'ApacheBAS-ASM v0.1.34.3: WHILE nesting limit exceeded.',0
msg_while_limit db 'ApacheBAS-ASM v0.1.34.3: WHILE iteration limit exceeded.',0
msg_bad_do db 'ApacheBAS-ASM v0.1.34.3: malformed DO/LOOP statement.',0
msg_missing_loop db 'ApacheBAS-ASM v0.1.34.3: DO without matching LOOP.',0
msg_unmatched_loop db 'ApacheBAS-ASM v0.1.34.3: LOOP without matching DO.',0
msg_do_depth db 'ApacheBAS-ASM v0.1.34.3: DO nesting limit exceeded.',0
msg_do_limit db 'ApacheBAS-ASM v0.1.34.3: DO iteration limit exceeded.',0
msg_bad_goto db 'ApacheBAS-ASM v0.1.34.3: GOTO requires a label or line number.',0
msg_missing_label db 'ApacheBAS-ASM v0.1.34.3: branch target was not found.',0
msg_goto_limit db 'ApacheBAS-ASM v0.1.34.3: GOTO jump limit exceeded.',0
msg_bad_gosub db 'ApacheBAS-ASM v0.1.34.3: GOSUB requires a label or line number.',0
msg_missing_return db 'ApacheBAS-ASM v0.1.34.3: subroutine reached the end of the program without RETURN.',0
msg_return_without_gosub db 'ApacheBAS-ASM v0.1.34.3: RETURN without GOSUB.',0
msg_gosub_depth db 'ApacheBAS-ASM v0.1.34.3: GOSUB nesting limit exceeded.',0
msg_gosub_limit db 'ApacheBAS-ASM v0.1.34.3: GOSUB call limit exceeded.',0
msg_division_zero db 'ApacheBAS-ASM v0.1.34.3: division by zero.',0
msg_bad_based_literal db 'ApacheBAS-ASM v0.1.34.3: malformed hexadecimal, octal or binary literal.',0
msg_based_literal_overflow db 'ApacheBAS-ASM v0.1.34.3: base-prefixed integer literal exceeds 32 bits.',0
msg_bad_option_base db 'ApacheBAS-ASM v0.1.34.3: OPTION BASE accepts only 0 or 1.',0
msg_option_base_late db 'ApacheBAS-ASM v0.1.34.3: OPTION BASE must appear before the first array DIM.',0
msg_bad_dim db 'ApacheBAS-ASM v0.1.34.3: malformed DIM statement.',0
msg_array_limit db 'ApacheBAS-ASM v0.1.34.3: maximum number of arrays exceeded.',0
msg_array_size db 'ApacheBAS-ASM v0.1.34.3: array bounds must form a range of at most 4096 elements within -4095..4095.',0
msg_array_not_dim db 'ApacheBAS-ASM v0.1.34.3: array was not dimensioned.',0
msg_array_bounds db 'ApacheBAS-ASM v0.1.34.3: array index is outside its bounds.',0
msg_array_index_numeric db 'ApacheBAS-ASM v0.1.34.3: array index must be an integer.',0
msg_bad_array_reference db 'ApacheBAS-ASM v0.1.34.3: malformed array reference.',0
msg_bad_read db 'ApacheBAS-ASM v0.1.34.3: malformed READ statement.',0
msg_out_of_data db 'ApacheBAS-ASM v0.1.34.3: READ reached the end of DATA.',0
msg_data_limit db 'ApacheBAS-ASM v0.1.34.3: DATA item limit exceeded.',0
msg_restore_label db 'ApacheBAS-ASM v0.1.34.3: RESTORE labels are not supported in this release.',0
msg_bad_swap db 'ApacheBAS-ASM v0.1.34.3: SWAP requires exactly two variable or array-element targets.',0
msg_bad_substring db 'ApacheBAS-ASM v0.1.34.3: LEFT$, RIGHT$ and MID$ require valid arguments.',0
msg_bad_asc db 'ApacheBAS-ASM v0.1.34.3: ASC requires a non-empty string.',0
msg_bad_sqr db 'ApacheBAS-ASM v0.1.34.3: SQR requires a non-negative integer.',0
msg_conversion_range db 'ApacheBAS-ASM v0.1.34.3: numeric conversion is outside the supported range.',0
msg_bad_real_argument db 'ApacheBAS-ASM v0.1.34.3: real function requires a valid signed decimal argument.',0
msg_bad_real_arithmetic db 'ApacheBAS-ASM v0.1.34.3: invalid or out-of-range decimal arithmetic operand.',0
msg_real_domain db 'ApacheBAS-ASM v0.1.34.3: LOG requires an argument greater than zero.',0
msg_real_range db 'ApacheBAS-ASM v0.1.34.3: real function result exceeds the supported range.',0
msg_bad_space db 'ApacheBAS-ASM v0.1.34.3: SPACE$ requires a non-negative count.',0
msg_bad_string db 'ApacheBAS-ASM v0.1.34.3: STRING$ requires a non-negative count and a non-empty character string.',0
msg_bad_sleep db 'ApacheBAS-ASM v0.1.34.3: SLEEP requires a non-negative number of seconds.',0
msg_input_cgi db 'ApacheBAS-ASM v0.1.34.3: INPUT is disabled in CGI mode.',0
msg_bad_input db 'ApacheBAS-ASM v0.1.34.3: malformed INPUT statement.',0
msg_input_read db 'ApacheBAS-ASM v0.1.34.3: INPUT could not read standard input.',0
msg_bad_include db 'ApacheBAS-ASM v0.1.34.3: INCLUDE requires a relative filename expression.',0
msg_include_depth db 'ApacheBAS-ASM v0.1.34.3: maximum INCLUDE depth exceeded.',0
msg_include_path db 'ApacheBAS-ASM v0.1.34.3: INCLUDE rejected an unsafe relative path.',0
msg_include_extension db 'ApacheBAS-ASM v0.1.34.3: INCLUDE accepts only .bas and .inc files.',0
msg_include_open db 'ApacheBAS-ASM v0.1.34.3: INCLUDE could not open the requested file.',0
msg_include_size db 'ApacheBAS-ASM v0.1.34.3: INCLUDE could not determine file size.',0
msg_include_large db 'ApacheBAS-ASM v0.1.34.3: included file exceeds 512 KiB.',0
msg_include_read db 'ApacheBAS-ASM v0.1.34.3: INCLUDE could not read the complete file.',0
msg_readfile_path db 'ApacheBAS-ASM v0.1.34.3: READFILE$/READHEX$ rejected an unsafe relative path.',0
msg_readfile_open db 'ApacheBAS-ASM v0.1.34.3: READFILE$/READHEX$ could not open the file.',0
msg_readfile_size db 'ApacheBAS-ASM v0.1.34.3: READFILE$/READHEX$ could not determine file size.',0
msg_readfile_large db 'ApacheBAS-ASM v0.1.34.3: file is too large for the expression buffer.',0
msg_readfile_read db 'ApacheBAS-ASM v0.1.34.3: READFILE$/READHEX$ could not read the complete file.',0
msg_readfile_binary db 'ApacheBAS-ASM v0.1.34.3: READFILE$ found NUL bytes; use READHEX$ for binary data.',0
msg_bad_saveupload db 'ApacheBAS-ASM v0.1.34.3: SAVEUPLOAD requires a filename expression.',0
file_err_syntax db 'WRITEFILE/APPENDFILE require path and content expressions.',0
file_err_path db 'Unsafe relative file path.',0
file_err_scope db 'WRITEFILE/APPENDFILE may write only below data/ and may not overwrite .bas/.inc source.',0
file_err_open db 'Could not open the destination file.',0
file_err_write db 'Could not write the complete file.',0
exec_err_syntax db 'EXEC requires an .exe name/path and optional single argument.',0
exec_err_tool db 'EXEC could not resolve the requested .exe locally or through Windows PATH.',0
exec_err_argument db 'EXEC argument is too long or contains a quote/newline.',0
exec_err_temp db 'EXEC could not obtain a temporary directory/file.',0
exec_err_temp_open db 'EXEC could not open its capture file.',0
exec_err_launch db 'EXEC could not start the requested executable.',0
exec_err_timeout db 'EXEC exceeded the 5 second time limit and was terminated.',0
exec_err_capture db 'EXEC completed but captured output could not be opened.',0
exec_err_capture_read db 'EXEC completed but captured output could not be read.',0
start_err_syntax db 'START requires an .exe name/path and optional single argument.',0
start_err_path db 'START could not resolve the requested .exe locally or through Windows PATH.',0
start_err_argument db 'START argument is too long or contains a quote/newline.',0
start_err_launch db 'START could not launch the requested executable.',0
upload_err_cgi db 'SAVEUPLOAD is available only through CGI.',0
upload_err_empty db 'The request body is empty.',0
upload_err_too_large db 'The upload exceeds the 1 MiB request-body limit.',0
upload_err_content_type db 'Use application/octet-stream or an image/* content type.',0
upload_err_filename db 'Unsafe filename or unsupported image extension.',0
upload_err_signature db 'The file signature does not match its image extension.',0
upload_err_path db 'The upload path is too long.',0
upload_err_open db 'The uploads directory or destination file could not be opened.',0
upload_err_write db 'The uploaded body could not be written completely.',0
msg_output_large db 'ApacheBAS-ASM: output exceeded the 4 MiB limit.'
msg_output_large_len = $-msg_output_large

crlf db 13,10
crlf_len = $-crlf
one_space db ' '

keyword_print db 'PRINT',0
keyword_if db 'IF',0
keyword_then db 'THEN',0
keyword_else db 'ELSE',0
keyword_rem db 'REM',0
keyword_randomize db 'RANDOMIZE',0
keyword_sleep db 'SLEEP',0
keyword_include db 'INCLUDE',0
keyword_writefile db 'WRITEFILE',0
keyword_appendfile db 'APPENDFILE',0
keyword_start db 'START',0
keyword_exec db 'EXEC',0
keyword_saveupload db 'SAVEUPLOAD',0
keyword_input db 'INPUT',0
keyword_cls db 'CLS',0
keyword_clear db 'CLEAR',0
keyword_clr db 'CLR',0
keyword_stop db 'STOP',0
keyword_end db 'END',0
keyword_not db 'NOT',0
keyword_for db 'FOR',0
keyword_to db 'TO',0
keyword_step db 'STEP',0
keyword_next db 'NEXT',0
keyword_while db 'WHILE',0
keyword_wend db 'WEND',0
keyword_do db 'DO',0
keyword_loop db 'LOOP',0
keyword_until db 'UNTIL',0
keyword_go_to db 'GO TO',0
keyword_goto db 'GOTO',0
keyword_gosub db 'GOSUB',0
keyword_return db 'RETURN',0
keyword_option_base db 'OPTION BASE',0
keyword_dim db 'DIM',0
keyword_data db 'DATA',0
keyword_read db 'READ',0
keyword_restore db 'RESTORE',0
keyword_swap db 'SWAP',0

op_word_or db 'OR',0
op_word_xor db 'XOR',0
op_word_and db 'AND',0
op_word_mod db 'MOD',0

token_true db 'TRUE',0
token_false db 'FALSE',0

operator_ne db '<>',0
operator_eq db '=',0
token_semicolon db ';',0
token_comma db ',',0

token_time db 'TIME$',0
token_date db 'DATE$',0
token_timer db 'TIMER',0
token_rnd db 'RND',0
token_pi db 'PI',0
text_pi db '3.141593',0
func_readfile db 'READFILE$',0
func_readhex db 'READHEX$',0
func_len db 'LEN',0
func_left db 'LEFT$',0
func_right db 'RIGHT$',0
func_mid db 'MID$',0
func_ucase db 'UCASE$',0
func_lcase db 'LCASE$',0
func_trim db 'TRIM$',0
func_ltrim db 'LTRIM$',0
func_rtrim db 'RTRIM$',0
func_html db 'HTML$',0
func_json db 'JSON$',0
func_str db 'STR$',0
func_val db 'VAL',0
func_cint db 'CINT',0
func_clng db 'CLNG',0
func_cdbl db 'CDBL',0
func_csng db 'CSNG',0
func_hex db 'HEX$',0
func_oct db 'OCT$',0
func_abs db 'ABS',0
func_sgn db 'SGN',0
func_int db 'INT',0
func_fix db 'FIX',0
func_sqr db 'SQR',0
func_sin db 'SIN',0
func_cos db 'COS',0
func_tan db 'TAN',0
func_atn db 'ATN',0
func_log db 'LOG',0
func_exp db 'EXP',0
func_asc db 'ASC',0
func_chr db 'CHR$',0
func_instr db 'INSTR',0
func_space db 'SPACE$',0
func_string db 'STRING$',0
type_string db 'STRING',0
func_lbound db 'LBOUND',0
func_ubound db 'UBOUND',0

digits_upper db '0123456789ABCDEF'
const_million dd 1000000

ent_amp db '&amp;'
ent_amp_len = $-ent_amp
ent_lt db '&lt;'
ent_lt_len = $-ent_lt
ent_gt db '&gt;'
ent_gt_len = $-ent_gt
ent_quot db '&quot;'
ent_quot_len = $-ent_quot
ent_apos db '&#39;'
ent_apos_len = $-ent_apos

mime_form_urlencoded db 'application/x-www-form-urlencoded',0
mime_octet_stream db 'application/octet-stream',0
mime_image_prefix db 'image/',0
upload_ext_png db 'png',0
upload_ext_jpg db 'jpg',0
upload_ext_jpeg db 'jpeg',0
upload_ext_gif db 'gif',0
upload_ext_webp db 'webp',0
upload_directory_leaf db 'uploads',0
upload_directory_relative db 'uploads',0
upload_url_prefix db 'uploads/',0
upload_text_zero db '0',0
upload_text_one db '1',0
text_zero db '0',0
text_one db '1',0
text_empty db 0
ext_bas db 'bas',0
ext_inc db 'inc',0
ext_exe db 'exe',0
prefix_data_forward db 'data/',0
prefix_data_back db 'data\',0
exec_temp_prefix db 'ABS',0
upload_text_empty db 0
prefix_get db 'GET_',0
prefix_post db 'POST_',0
prefix_cookie db 'COOKIE_',0

; Environment variable names.
env_path_translated db 'PATH_TRANSLATED',0
env_script_filename db 'SCRIPT_FILENAME',0
env_request_method db 'REQUEST_METHOD',0
env_query_string db 'QUERY_STRING',0
env_content_type db 'CONTENT_TYPE',0
env_content_length db 'CONTENT_LENGTH',0
env_http_cookie db 'HTTP_COOKIE',0
env_remote_addr db 'REMOTE_ADDR',0
env_script_name db 'SCRIPT_NAME',0
env_request_uri db 'REQUEST_URI',0
env_server_protocol db 'SERVER_PROTOCOL',0
env_server_name db 'SERVER_NAME',0
env_server_port db 'SERVER_PORT',0
env_http_host db 'HTTP_HOST',0
env_http_user_agent db 'HTTP_USER_AGENT',0
env_http_referer db 'HTTP_REFERER',0
env_http_accept db 'HTTP_ACCEPT',0
env_http_accept_language db 'HTTP_ACCEPT_LANGUAGE',0

; BASIC variable names.
var_server_method db 'SERVER_REQUEST_METHOD$',0
var_request_method db 'REQUEST_METHOD$',0
var_server_query db 'SERVER_QUERY_STRING$',0
var_query_string db 'QUERY_STRING$',0
var_server_body db 'SERVER_BODY$',0
var_server_content_type db 'SERVER_CONTENT_TYPE$',0
var_content_type db 'CONTENT_TYPE$',0
var_server_content_length db 'SERVER_CONTENT_LENGTH$',0
var_content_length db 'CONTENT_LENGTH$',0
var_server_cookie db 'SERVER_COOKIE$',0
var_server_remote_addr db 'SERVER_REMOTE_ADDR$',0
var_server_script_name db 'SERVER_SCRIPT_NAME$',0
var_server_script_filename db 'SERVER_SCRIPT_FILENAME$',0
var_server_request_uri db 'SERVER_REQUEST_URI$',0
var_server_protocol db 'SERVER_PROTOCOL$',0
var_server_name db 'SERVER_NAME$',0
var_server_port db 'SERVER_PORT$',0
var_server_http_host db 'SERVER_HTTP_HOST$',0
var_server_user_agent db 'SERVER_USER_AGENT$',0
var_server_referer db 'SERVER_REFERER$',0
var_server_accept db 'SERVER_ACCEPT$',0
var_server_accept_language db 'SERVER_ACCEPT_LANGUAGE$',0
var_upload_ok db 'UPLOAD_OK',0
var_upload_size db 'UPLOAD_SIZE',0
var_upload_name db 'UPLOAD_NAME$',0
var_upload_file db 'UPLOAD_FILE$',0
var_upload_url db 'UPLOAD_URL$',0
var_upload_error db 'UPLOAD_ERROR$',0
var_file_ok db 'FILE_OK',0
var_file_size db 'FILE_SIZE',0
var_file_path db 'FILE_PATH$',0
var_file_error db 'FILE_ERROR$',0
var_exec_ok db 'EXEC_OK',0
var_exec_code db 'EXEC_CODE',0
var_exec_output db 'EXEC_OUTPUT$',0
var_exec_error db 'EXEC_ERROR$',0
var_start_ok db 'START_OK',0
var_start_error db 'START_ERROR$',0

; ----------------------------------------------------------------------------
; Writable storage
; ----------------------------------------------------------------------------

section '.bss' data readable writeable

script_buffer rd 1
body_buffer rd 1
output_buffer rd 1
script_handle rd 1
script_length rd 1
request_body_length rd 1
request_body_advertised_length rd 1
stdin_handle rd 1
cgi_mode rd 1
input_skip_lf rd 1
input_bytes rd 1
input_char rb 1
input_span_start rd 1
input_span_length rd 1
input_name rb VAR_NAME_SIZE
input_buffer rb VAR_VALUE_SIZE
upload_handle rd 1
upload_directory rb PATH_SIZE
upload_full_path rb PATH_SIZE
upload_public_url rb PATH_SIZE
upload_size_text rb 32
file_handle rd 1
file_relative_path rb PATH_SIZE
file_full_path rb PATH_SIZE
file_binary_buffer rb MAX_FILE_BINARY+1
file_operation_size rd 1
file_size_text rb 32
include_depth rd 1
include_handle rd 1
include_length rd 1
include_current_buffer rd 1
include_full_path rb PATH_SIZE
include_buffers rb MAX_INCLUDE_DEPTH*MAX_INCLUDE_SIZE
include_saved_data_count rd MAX_INCLUDE_DEPTH
include_saved_data_index rd MAX_INCLUDE_DEPTH
include_saved_data_initialized rd MAX_INCLUDE_DEPTH
include_data_backups rb MAX_INCLUDE_DEPTH*MAX_DATA_ITEMS*DATA_ITEM_SIZE
exec_work_directory rb PATH_SIZE
exec_full_path rb PATH_SIZE
exec_tool_name rb PATH_SIZE
exec_command_line rb MAX_EXEC_COMMAND
exec_temp_directory rb PATH_SIZE
exec_temp_file rb PATH_SIZE
exec_output_buffer rb EXEC_OUTPUT_SIZE
exec_output_length rd 1
exec_output_truncated rd 1
exec_output_probe rd 1
exec_code_text rb 32
exec_exit_code rd 1
exec_output_handle rd 1
exec_read_handle rd 1
exec_timed_out rd 1
exec_build_result rd 1
exec_security_attributes rb 12
exec_startup_info rb 68
exec_process_info rb 16
output_length rd 1
output_truncated rd 1
response_status_code rd 1
response_status_line_length rd 1
response_status_line rb 96
response_content_type rb CONTENT_TYPE_SIZE
response_custom_headers_length rd 1
response_custom_headers rb MAX_CUSTOM_HEADERS+1
directive_buffer rb DIRECTIVE_SIZE
runtime_error rd 1
fpu_operation rd 1
fpu_scaled_input rd 1
fpu_scaled_output rd 1
fpu_fraction_digits rd 1
fpu_fraction_value rd 1
fpu_integer_check rd 1
bytes_done rd 1
file_size64 rq 1

variable_count rd 1
variable_names rb MAX_VARIABLES*VAR_NAME_SIZE
variable_values rb MAX_VARIABLES*VAR_VALUE_SIZE
array_count rd 1
option_base rd 1
array_names rb MAX_ARRAYS*VAR_NAME_SIZE
array_lower rd MAX_ARRAYS
array_upper rd MAX_ARRAYS
array_string rb MAX_ARRAYS
array_last_is_string rd 1
array_name_temp rb VAR_NAME_SIZE
data_item_count rd 1
data_read_index rd 1
data_initialized rd 1
data_items rb MAX_DATA_ITEMS*DATA_ITEM_SIZE

script_path rb PATH_SIZE
env_buffer rb ENV_SIZE
url_key rb VAR_NAME_SIZE
url_value rb VAR_VALUE_SIZE
var_build_name rb VAR_NAME_SIZE
assignment_name rb VAR_NAME_SIZE
swap_name_a rb VAR_NAME_SIZE
swap_name_b rb VAR_NAME_SIZE
swap_value_a rb EVAL_SIZE
swap_value_b rb EVAL_SIZE
runtime_error_message rb 1024
eval_buffer rb EVAL_SIZE
eval_temp rb EVAL_SIZE
expr_return_length rd 1
eval_work_depth rd 1
eval_work_buffers rb EVAL_WORK_SLOTS*EVAL_WORK_SIZE
binary_left_num rd 1
binary_right_num rd 1
binary_left_scaled rd 1
binary_right_scaled rd 1
intfix_mode rd 1
conversion_mode rd 1
scan_best_ptr rd 1
scan_best_prec rd 1
scan_best_kind rd 1
scan_best_len rd 1
scan_start rd 1
scan_depth rd 1
scan_quote rd 1
system_time rw 8
rnd_seed rd 1
sleep_fraction rd 1

parse_prefix rd 1
if_condition_result rd 1
if_then_ptr rd 1
if_then_len rd 1
if_else_ptr rd 1
template_cursor rd 1
template_end rd 1
tag_pointer rd 1
tag_close_pointer rd 1
tag_type rd 1
tag_open_length rd 1
print_had_item rd 1
print_trailing_semicolon rd 1

for_depth rd 1
for_names rb MAX_FOR_DEPTH*VAR_NAME_SIZE
for_value_buffer rb 32
while_depth rd 1
do_depth rd 1
flow_pending rd 1
flow_target rd 1
goto_jump_count rd 1
gosub_depth rd 1
gosub_call_count rd 1
return_pending rd 1
program_stop rd 1
current_statement_ptr rd 1
current_statement_len rd 1
active_program_start rd 1
active_program_end rd 1
goto_label_name rb VAR_NAME_SIZE

; ----------------------------------------------------------------------------
; Manual PE import table. No include files are required.
; ----------------------------------------------------------------------------

section '.idata' import data readable writeable

        dd rva kernel32_lookup,0,0,rva kernel32_name,rva kernel32_iat
        dd 0,0,0,0,0

kernel32_name db 'KERNEL32.DLL',0
align 2

hn_CloseHandle            dw 0
                          db 'CloseHandle',0
align 2
hn_CreateDirectoryA       dw 0
                          db 'CreateDirectoryA',0
align 2
hn_CreateFileA            dw 0
                          db 'CreateFileA',0
align 2
hn_CreateProcessA         dw 0
                          db 'CreateProcessA',0
align 2
hn_DeleteFileA            dw 0
                          db 'DeleteFileA',0
align 2
hn_ExitProcess            dw 0
                          db 'ExitProcess',0
align 2
hn_GetEnvironmentVariableA dw 0
                          db 'GetEnvironmentVariableA',0
align 2
hn_GetFileSizeEx          dw 0
                          db 'GetFileSizeEx',0
align 2
hn_GetExitCodeProcess     dw 0
                          db 'GetExitCodeProcess',0
align 2
hn_GetLocalTime           dw 0
                          db 'GetLocalTime',0
align 2
hn_GetStdHandle           dw 0
                          db 'GetStdHandle',0
align 2
hn_GetTempPathA           dw 0
                          db 'GetTempPathA',0
align 2
hn_GetTempFileNameA       dw 0
                          db 'GetTempFileNameA',0
align 2
hn_ReadFile               dw 0
                          db 'ReadFile',0
align 2
hn_SetFilePointer         dw 0
                          db 'SetFilePointer',0
align 2
hn_SearchPathA             dw 0
                          db 'SearchPathA',0
align 2
hn_Sleep                  dw 0
                          db 'Sleep',0
align 2
hn_TerminateProcess       dw 0
                          db 'TerminateProcess',0
align 2
hn_VirtualAlloc           dw 0
                          db 'VirtualAlloc',0
align 2
hn_WaitForSingleObject    dw 0
                          db 'WaitForSingleObject',0
align 2
hn_WriteFile              dw 0
                          db 'WriteFile',0
align 4

kernel32_lookup:
        dd rva hn_CloseHandle
        dd rva hn_CreateDirectoryA
        dd rva hn_CreateFileA
        dd rva hn_CreateProcessA
        dd rva hn_DeleteFileA
        dd rva hn_ExitProcess
        dd rva hn_GetEnvironmentVariableA
        dd rva hn_GetFileSizeEx
        dd rva hn_GetExitCodeProcess
        dd rva hn_GetLocalTime
        dd rva hn_GetStdHandle
        dd rva hn_GetTempPathA
        dd rva hn_GetTempFileNameA
        dd rva hn_ReadFile
        dd rva hn_SetFilePointer
        dd rva hn_SearchPathA
        dd rva hn_Sleep
        dd rva hn_TerminateProcess
        dd rva hn_VirtualAlloc
        dd rva hn_WaitForSingleObject
        dd rva hn_WriteFile
        dd 0

kernel32_iat:
CloseHandle             dd rva hn_CloseHandle
CreateDirectoryA        dd rva hn_CreateDirectoryA
CreateFileA             dd rva hn_CreateFileA
CreateProcessA          dd rva hn_CreateProcessA
DeleteFileA             dd rva hn_DeleteFileA
ExitProcess             dd rva hn_ExitProcess
GetEnvironmentVariableA dd rva hn_GetEnvironmentVariableA
GetFileSizeEx           dd rva hn_GetFileSizeEx
GetExitCodeProcess      dd rva hn_GetExitCodeProcess
GetLocalTime            dd rva hn_GetLocalTime
GetStdHandle            dd rva hn_GetStdHandle
GetTempPathA            dd rva hn_GetTempPathA
GetTempFileNameA        dd rva hn_GetTempFileNameA
ReadFile                dd rva hn_ReadFile
SetFilePointer          dd rva hn_SetFilePointer
SearchPathA             dd rva hn_SearchPathA
Sleep                   dd rva hn_Sleep
TerminateProcess        dd rva hn_TerminateProcess
VirtualAlloc            dd rva hn_VirtualAlloc
WaitForSingleObject     dd rva hn_WaitForSingleObject
WriteFile               dd rva hn_WriteFile
                        dd 0

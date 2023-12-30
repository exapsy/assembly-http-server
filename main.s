section .data
	error_message		db "An error occured", 0xA	; error message
	error_message_len	equ $-error_message		; length of the error message
	server_fd		dd 0				; server file descriptor
	client_fd		dd 0				; client file descriptor
	port			dw 0x1F90			; port number (8080)
	addr			db 127, 0, 0, 1			; localhost address (127.0.0.1)
	addrlen			db 16				; length of the address
	http_response   	db "HTTP/1.1 200 OK", 0xA	; "0xA" is newline hexadecimal
				db "Content-Length: 3", 0xA
				db "Content-Type: text/plain", 0xA
				db 0xA,0xA,0x0	; Extra newline to separate headers from body "OK",0xA
	response_len		equ $-http_response	; Length of the HTTP response, $ represents current address, http_response the address of the start of the response, so $ - http_response = length of bytes assigned to http_response

section .bss
	sockaddr		resb 16		; struct sockaddr_in
	client_addr		resb 16		; client address

section .text
global _start

; uses syscall `exit`
; which uses `ebx` register
; to determine the exit status
program_exit:
	mov eax, 0x1
	int 0x80

; exits with 0 (normal exit)
program_exit_normal:
	mov ebx, 0		; 0 for normal exit
	jmp near program_exit	; exit normally

; exits with 1 (error exit)
program_exit_error:
	mov ebx, 1		; 1 for error exit
	jmp near program_exit	; exit with error

; Function to calculate the length of a null-terminated string
strlen:
    push ebx
    xor ebx, ebx          ; Clear ebx to use it as a counter

no_custom_error:
    jmp program_exit_error  ; Exit with an error status

; writes to stdout an error message and exits with error status
error_handling:
	mov eax, 4			; syscall for write
	mov ebx, 1			; file descriptor 1 (stdout)
	mov ecx, error_message		; error message's address
	mov edx, error_message_len	; error messge's length
	int 0x80			; make syscall

	; Check if a custom error message is provided (length > 0)
	mov eax, [esp + 8]  ; Load the address of the custom error message
	test eax, eax       ; Check if it's not null (length > 0)
	jz no_custom_error ; If not, skip writing custom error

	; Write the custom error message
	mov eax, 4          ; syscall for write
	mov ebx, 1          ; file descriptor 1 (stdout)
	mov ecx, [esp + 8]  ; custom error message's address
	call strlen         ; Calculate the length of the custom error message
	mov edx, eax        ; Store the length in edx
	int 0x80            ; make syscall

	jmp program_exit_error

; checks if syscall returned error code 
; if not, then returns back
handle_syscall_ret_and_err:
	cmp eax, 0 		; compare syscall's return to 0
	js error_handling	; jmp to error handling if syscall's return < 0

create_socket:
	; Create socket (socket(AF_INET, SOCK_STREAM, 0))
	mov eax, 0x66				; syscall number for socketcall
	mov ebx, 0x1				; SYS_SOCKET
	push 0x0				; protocol (IPPROTO_IP)
	push 0x1				; type (SOCK_STREAM)
	push 0x2				; domain (AF_INET)
	mov ecx, esp				; pointer to arguments
	int 0x80				; make syscall
	mov [server_fd], eax			; store server file descriptor

	call handle_syscall_ret_and_err

bind_socket:
	; Prepare sockaddr_in structure
	xor eax, eax
	mov byte [sockaddr], 0x2		; AF_INET
	mov ax, [port]               		; Move the word-sized port number into AX
	mov [sockaddr + 2], ax       		; Move AX into the sockaddr structure

    	; Move IP address into the sockaddr structure
	mov eax, [addr]              		; Move the dword-sized IP address into EAX
	mov [sockaddr + 4], eax      		; Move EAX into the sockaddr structure
	mov dword [sockaddr + 8], eax		; zero rest of the structure

	; Bind socket (bind(server_fd, sockaddr, sizeof(sockaddr))
	mov eax, 0x66				; syscall number for socketcall
	mov ebx, 0x2				; SYS_BIND
	push dword addrlen			; addrlen
	push dword sockaddr			; sockaddr
	push dword [server_fd]			; server_fd
	mov ecx, esp				; pointer to arguments
	int 0x80				; make syscall

	call near handle_syscall_ret_and_err

listen_on_socket:
	; Listen on socket (listen(server_fd, backlog))
	mov eax, 0x66 				; syscall number for socketcall
	mov ebx, 0x4				; SYS_LISTEN
	push 0x2				; backlog
	push dword [server_fd]			; server_fd
	mov ecx, esp				; pointer to arguments
	int 0x80				; make syscall

	call near handle_syscall_ret_and_err

accept_connections:
	mov [client_fd], eax			; store client file descriptor

	; Accept connection (accept(server_fd, NULL, NULL))
	mov eax, 0x66				; syscall number for socketcall
	mov ebx, 0x5				; SYS_ACCEPT
	lea ecx, [client_addr]			; client_addr
	lea edx, [addrlen]			; addrlen
	mov esi, [server_fd]			; server_fd
	mov ecx, esp				; pointer to arguments
	int 0x80

	call near handle_syscall_ret_and_err

send_response:
	mov [client_fd], eax			; store client file descriptor

	; Send HTTP response (send(client_fd, http_response, response_len, 0))
	mov eax, 0x66				; syscall number for socketcall
	mov ebx, 0x9				; SYS_SEND
	push 0x0
	push response_len			; flags
	push http_response			; pointer to the HTTP response
	push dword [client_fd]			; client file descriptor
	mov ecx, esp				; pointer to arguments
	int 0x80

	call near handle_syscall_ret_and_err

close_client_socket:
	; Close client socket (socket(client_fd))
	mov eax, 0x6				; syscall number for close
	mov ebx, [client_fd]			; client_fd
	int 0x80				; make syscall

	call near handle_syscall_ret_and_err

close_server_socket:
	; Close server socket (close(server_fd))
	mov eax, 0x6				; syscall number for close
	mov ebx, [server_fd]			; server_fd
	int 0x80				; make syscall

	call near handle_syscall_ret_and_err

_start:
	call create_socket
	call bind_socket
	call listen_on_socket
	call accept_connections
	call send_response
	call close_client_socket
	call close_server_socket
	jmp program_exit_normal


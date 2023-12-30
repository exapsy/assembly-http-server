.PHONY: run
run:
	nasm -f elf32 ./main.s -o tcp_server.o
	ld -m elf_i386 tcp_server.o -o tcp_server
	./tcp_server

; read a command line argument from the buffer at hl;
; copy to buffer at de, up to bc bytes in size, and null-terminate.
get_command_arg
	ld a,(hl)
	; argument is terminated by space, colon, newline or null
	or a
	jr z,get_command_arg_done
	cp ' '
	jr z,get_command_arg_done
	cp ':'
	jr z,get_command_arg_done
	cp 0x0d
	jr z,get_command_arg_done
	ldi
	jp pe,get_command_arg
get_command_arg_done
	xor a
	ld (de),a	; null-terminate argument
	ret
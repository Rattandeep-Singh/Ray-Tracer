format ELF64 executable 3
entry start

segment readable executable

SYS_READ  = 0
SYS_WRITE = 1
SYS_OPEN  = 2
SYS_CLOSE = 3
SYS_EXIT  = 60

O_CREAT  = 64
O_WRONLY = 1
O_TRUNC  = 512

WIDTH  = 256
HEIGHT = 256

start:
    ; open output.ppm
    mov rax, SYS_OPEN
    mov rdi, filename
    mov rsi, O_CREAT + O_WRONLY + O_TRUNC
    mov rdx, 644o
    syscall
    mov [fd], rax

    ; write PPM header
    mov rax, SYS_WRITE
    mov rdi, [fd]
    mov rsi, ppm_header
    mov rdx, ppm_header_len
    syscall


    ; oc = ray_origin - sphere_center (ymm12,13,14)
	vmovups ymm12, yword [cam_x]
	vsubps ymm12, ymm12, yword [sphere_x]
	vmovups ymm13, yword [cam_y]
	vsubps ymm13, ymm13, yword [sphere_y]
	vmovups ymm14, yword [cam_z]
	vsubps ymm14, ymm14, yword [sphere_z]

	;4c = 4(dot(oc, oc) - r^2) (ymm15)
	vmulps ymm15, ymm12, ymm12
	vmulps ymm0, ymm13, ymm13
	vaddps ymm15, ymm15, ymm0
	vmulps ymm0, ymm14, ymm14
	vaddps ymm15, ymm15, ymm0
	vmovups ymm0, yword [sphere_r]
	vmulps ymm0, ymm0, yword [sphere_r]
	vsubps ymm15, ymm15, ymm0
	vaddps ymm15, ymm15, ymm15
	vaddps ymm15, ymm15, ymm15

	xor r11d, r11d ; pixel_offset = 0
    xor r12d, r12d ; y = 0
y_loop:
    cmp r12d, HEIGHT
    jge done

	vmovd xmm0, r12d
	vpbroadcastd ymm1, xmm0
	vcvtdq2ps ymm1, ymm1
    vdivps ymm1, ymm1, yword [fh]
	vaddps ymm1, ymm1, ymm1
    vsubps ymm1, ymm1, yword [one]
    vxorps ymm1, ymm1, yword [signmask]
	vmulps ymm3, ymm1, ymm1

    xor r13d, r13d ; x = 0
x_loop:
    cmp r13d, WIDTH-7
    jge next_row

    vmovd xmm0, r13d
	vpbroadcastd ymm0, xmm0
	vpaddd ymm0, ymm0, yword [x_offsets]
	vcvtdq2ps ymm0, ymm0
	    
    ; map pixel to [-1,1]
	vdivps ymm0, ymm0, yword [fw]
    vaddps ymm0, ymm0, ymm0
    vsubps ymm0, ymm0, yword [one]

	vmovups ymm2, ymm1
	
    ; ray dir = normalize(x,y,1) (ymm0,2,4)
	vmulps ymm5, ymm0, ymm0
	vaddps ymm5, ymm5, ymm3
	vaddps ymm5, ymm5, yword [one]

    vrsqrtps ymm5, ymm5

    vmulps ymm0, ymm0, ymm5
    vmulps ymm2, ymm2, ymm5
    vmovups ymm4, yword [one]
	vmulps ymm4, ymm4, ymm5

    ; b = 2 * dot(oc,d) (ymm5)
	vmulps ymm5, ymm12, ymm0
	vmulps ymm6, ymm13, ymm2
	vaddps ymm5, ymm5, ymm6
	vmulps ymm6, ymm14, ymm4
	vaddps ymm5, ymm5, ymm6
	vaddps ymm5, ymm5, ymm5

    ; discriminant = b*b - 4*c (ymm6)
    vmulps ymm6, ymm5, ymm5
    vsubps ymm6, ymm6, ymm15

	; mask (ymm11)
	vcmpgeps ymm11, ymm6, yword [zero]

	vmaxps ymm6, ymm6, yword [zero]
    vsqrtps ymm6, ymm6

    ; t = (-b - sqrt(discriminant)) / 2 (ymm7)
	vaddps ymm7, ymm5, ymm6
	vxorps ymm7, ymm7, yword [signmask]
	vmulps ymm7, ymm7, yword [half]

    ; hit point (ymm8,9,10)
    vmulps ymm8, ymm7, ymm0
    vaddps ymm8, ymm8, yword [cam_x]

    vmulps ymm9, ymm7, ymm2
	vaddps ymm9, ymm9, yword [cam_y]
	
    vmulps ymm10, ymm7, ymm4
	vaddps ymm10, ymm10, yword [cam_z]
	
    ; N = (h - sphere) / radius (ymm5,6,7)
	vsubps ymm5, ymm8, yword [sphere_x]
	vdivps ymm5, ymm5, yword [sphere_r]

	vsubps ymm6, ymm9, yword [sphere_y]
	vdivps ymm6, ymm6, yword [sphere_r]

	vsubps ymm7, ymm10, yword [sphere_z]
	vdivps ymm7, ymm7, yword [sphere_r]

	; -L = -light + H (ymm8,9,10)
	vsubps ymm8, ymm8, yword [light_x]
	vsubps ymm9, ymm9, yword [light_y]
	vsubps ymm10, ymm10, yword [light_z]
	
	; Normalisation
	vmulps ymm0, ymm8, ymm8
	vmulps ymm2, ymm9, ymm9
	vaddps ymm0, ymm0, ymm2
	vmulps ymm2, ymm10, ymm10
	vaddps ymm0, ymm0, ymm2
	vrsqrtps ymm0, ymm0
	vmulps ymm8, ymm8, ymm0
	vmulps ymm9, ymm9, ymm0
	vmulps ymm10, ymm10, ymm0

	; N . L
	vmulps ymm0, ymm5, ymm8
	vmulps ymm2, ymm6, ymm9
	vaddps ymm0, ymm0, ymm2
	vmulps ymm2, ymm7, ymm10
	vaddps ymm0, ymm0, ymm2
	vxorps ymm0, ymm0, yword [signmask]
	
	vmaxps ymm0, ymm0, yword [zero]
	vminps ymm0, ymm0, yword [one]
    vmulps ymm0, ymm0, yword [twofiftyfive]
	vandps ymm0, ymm0, ymm11
	
	vcvtps2dq ymm0, ymm0
	vpackssdw ymm0, ymm0, ymm0
	vpackuswb ymm0, ymm0, ymm0

    vextractf128 xmm2, ymm0, 1 
    vpshufb xmm0, xmm0, xword [shuffle_mask]  
    vpshufb xmm2, xmm2, xword [shuffle_mask]  
    
    vmovdqu xword [pixel + r11d], xmm0             
    vmovdqu xword [pixel + r11d + 12], xmm2        
    add r11d, 24

    add r13d, 8
    jmp x_loop

next_row:
    inc r12d
    jmp y_loop

done:

    mov rax, SYS_WRITE
    mov rdi, [fd]
    mov rsi, pixel
    mov rdx, 196608
    syscall
    
    mov rax, SYS_CLOSE
    mov rdi, [fd]
    syscall

    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall

segment readable writeable

fd dq 0

filename db 'output.ppm',0

ppm_header db 'P6',10,'256 256',10,'255',10
ppm_header_len = $ - ppm_header

pixel rb 196608

fw dd 8 dup(256.0)
fh dd 8 dup(256.0)

zero dd 8 dup(0.0)
one dd 8 dup(1.0)
half dd 8 dup(0.5)
twofiftyfive dd 8 dup(255.0)

align 16
shuffle_mask:
	db 0,0,0, 1,1,1, 2,2,2, 3,3,3, 0,0,0,0

; Camera position
cam_x dd 8 dup(0.0)
cam_y dd 8 dup(0.0)
cam_z dd 8 dup(-3.0)

; Light position
light_x dd 8 dup(-2.0)
light_y dd 8 dup(2.0)
light_z dd 8 dup(-3.0)

; Sphere parameters
sphere_x dd 8 dup(0.5)
sphere_y dd 8 dup(0.0)
sphere_z dd 8 dup(0.0)
sphere_r dd 8 dup(1.5)


x_offsets: dd 0,1,2,3,4,5,6,7

align 32
signmask:
    dd 8 dup(0x80000000)

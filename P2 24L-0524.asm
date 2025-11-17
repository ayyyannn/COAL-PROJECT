;roll no: 24l-0524

[org 0x0100]              

jmp start                


; all game variables stored here

; game state variables
carLane: db 1              ; current lane of player's car (0=left, 1=center, 2=right)
score: dw 0                ; player's score (16-bit for large numbers)
gameRunning: db 1          ; game state flag (1=running, 0=stopped)
scrollCounter: db 0        ; counter to control animation speed
scrollOffset: db 0         ; offset for creating scrolling effect
scoreCounter: db 0         ; counter to slow down score increment

; obstalce (enemy car) management - can have up to 6 enemies on screen
obstacleCount: db 0        ; number of active obstacles
obstacleLanes: times 6 db 0  ; which lane each obstacle is in (0-2)
obstacleRows: times 6 db 0   ; which row each obstacle is at (0-24)

; bonus object ($) management - can have up to 3 bonuses on screen
bonusCount: db 0           ; number of active bonuses
bonusLanes: times 3 db 0   ; which lane each bonus is in
bonusRows: times 3 db 0    ; which row each bonus is at
lastBonusSpawn: db 0       ; frames since last bonus spawned (prevents clustering)

; lane occupation tracking (for spawning logic)
laneOccupied: times 3 db 0  ; flags: 1 if lane has obstacle at top, 0 if free

; screen layout constants
SCREEN_WIDTH equ 80        ; standard text mode width
SCREEN_HEIGHT equ 25       ; standard text mode height
ROAD_LEFT equ 25           ; road starts at column 25
ROAD_WIDTH equ 30          ; road is 30 columns wide
LANE_WIDTH equ 10          ; each lane is 10 columns wide

; color attribute constants (4-bit background + 4-bit foreground)
COLOR_ROAD equ 08h         ; dark gray road
COLOR_GRASS equ 20h        ; light green background
COLOR_CAR equ 0Ch          ; light red car
COLOR_OBSTACLE equ 09h     ; light blue enemy cars
COLOR_BONUS equ 0Eh        ; yellow bonus objects
COLOR_LINE equ 0Fh         ; white lane dividers
COLOR_TREE equ 06h         ; brown trees

; text messages displayed in game
msgScore: db 'Score: ', 0
msgGameOver: db 'GAME OVER!', 0
msgFinalScore: db 'Final Score: ', 0

; ========== subroutines ==========

; clear screen - fills entire screen with light green background
; no parameters
; modifies: es, ax, cx, di
clrscr:
    push es                ; save registers we'll modify
    push ax
    push cx
    push di
    
    mov ax, 0xb800         ; video memory segment for text mode
    mov es, ax
    xor di, di             ; start at offset 0 (top-left corner)
    mov ax, 0x2020         ; ah=20h (green bg), al=20h (space char)
    mov cx, 2000           ; 80 cols × 25 rows = 2000 characters
    cld                    ; clear direction flag (increment di)
    rep stosw              ; repeat: store ax at es:di, increment di by 2
    
    pop di                 ; restore registers
    pop cx
    pop ax
    pop es
    ret

; print string - displays null-terminated string at specified position
; parameters (pushed on stack): row, column, string offset
; modifies: es, ax, bx, cx, dx, si, di
printstr:
    push bp                ; set up stack frame for parameter access
    mov bp, sp
    push es                ; save registers
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    
    mov ax, 0xb800         ; video memory segment
    mov es, ax
    
    ; calculate screen position: offset = (row * 80 + col) * 2
    mov ax, SCREEN_WIDTH   ; ax = 80
    mul byte [bp+8]        ; multiply by row parameter
    add ax, [bp+6]         ; add column parameter
    shl ax, 1              ; multiply by 2 (each char = 2 bytes)
    mov di, ax             ; di now points to screen position
    
    mov si, [bp+4]         ; si points to string
    mov ah, 0x0F           ; ah = attribute (white on black)
    
.nextchar:
    lodsb                  ; load byte from ds:si into al, increment si
    cmp al, 0              ; check for null terminator
    je .done
    stosw                  ; store ax (char + attribute) at es:di
    jmp .nextchar
    
.done:
    pop di                 ; restore all registers
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    pop es
    pop bp
    ret 6                  ; return and clean 6 bytes of parameters from stack

; print number - converts number to decimal and displays it
; parameters (pushed on stack): row, column, number
; modifies: es, ax, bx, cx, dx, di
printnum:
    push bp                ; set up stack frame
    mov bp, sp
    push ax                ; save registers
    push bx
    push cx
    push dx
    push di
    push es
    
    mov ax, [bp+4]         ; get number to print
    mov bx, 10             ; divisor for decimal conversion
    xor cx, cx             ; cx = digit counter
    
    ; extract digits by repeated division by 10
.nextdigit:
    xor dx, dx             ; clear dx for division
    div bx                 ; ax = quotient, dx = remainder (digit)
    add dl, '0'            ; convert digit to ascii
    push dx                ; save digit on stack (reverses order)
    inc cx                 ; count this digit
    test ax, ax            ; check if quotient is 0
    jnz .nextdigit         ; if not, continue extracting digits
    
    ; calculate screen position
    mov ax, 0xb800
    mov es, ax
    mov ax, SCREEN_WIDTH
    mul byte [bp+8]        ; multiply by row
    add ax, [bp+6]         ; add column
    shl ax, 1              ; multiply by 2
    mov di, ax
    
    ; pop and print digits (now in correct order)
.printloop:
    pop dx                 ; get digit from stack
    mov dh, 0x0F           ; white on black attribute
    mov [es:di], dx        ; write to video memory
    add di, 2              ; move to next character position
    loop .printloop        ; repeat cx times
    
    pop es                 ; restore registers
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 6                  ; clean parameters from stack

; calculate screen position - converts row/col to video memory offset
; input: dh = row, dl = column
; output: di = offset in video memory
; formula: offset = (row * 80 + col) * 2
calcScreenPos:
    push ax                ; save registers
    push bx
    
    mov al, SCREEN_WIDTH   ; al = 80
    mul dh                 ; ax = row * 80
    mov bl, dl             ; bx = column
    xor bh, bh
    add ax, bx             ; ax = row * 80 + col
    shl ax, 1              ; ax = (row * 80 + col) * 2
    mov di, ax             ; return result in di
    
    pop bx                 ; restore registers
    pop ax
    ret

; get random number - uses real-time clock for true randomness
; no parameters
; returns: al = random number (0-59)
; uses rtc seconds register which changes unpredictably
getRandom:
    push dx                ; save dx
    
    mov al, 0x00           ; command: read seconds from rtc
    out 0x70, al           ; send command to rtc command port
    jmp .d1                ; small delay (rtc needs time to process)
.d1:
    in al, 0x71            ; read result from rtc data port
    
    ; convert from bcd (binary coded decimal) to binary
    ; bcd format: high nibble = tens digit, low nibble = ones digit
    ; example: 0x47 means 47 seconds
    mov ah, al             ; save copy
    and al, 0x0F           ; al = ones digit (low nibble)
    shr ah, 4              ; ah = tens digit (high nibble)
    mov dl, 10
    mul dl                 ; al = tens * 10
    add al, ah             ; al = tens*10 + ones = binary value
    
    pop dx                 ; restore dx
    ret

; Draw Screen - Renders scrolling terrain, road, and trees
; This creates the illusion of downward movement
; No parameters
; Modifies: ES, AX, BX, CX, DX, DI
drawScreen:
    push es                ; Save all registers we'll use
    push ax
    push bx
    push cx
    push dx
    push di
    
    mov ax, 0xb800         ; Video memory segment
    mov es, ax
    
    mov dh, 0              ; Start at row 0
    
.rowLoop:                  ; Loop through each row of screen
    mov dl, 0              ; Start at column 0
    
    ; Calculate scrolled row for animation effect
    ; By subtracting scrollOffset, trees appear to move DOWN
    mov al, dh             ; AL = current row
    sub al, [scrollOffset] ; AL = scrolled row position
    mov bl, al             ; BL = scrolled row (used for tree pattern)
    
    ; === Draw Left Terrain (25 columns) ===
    mov cx, ROAD_LEFT      ; CX = 25 columns
.leftTerrain:
    call calcScreenPos     ; Get video memory position
    
    ; Check if a tree should be drawn at this position
    ; Trees are at fixed scrolled rows (5, 13, 21, 29)
    mov al, bl
    and al, 0x1F           ; Wrap at 32 rows (creates repeating pattern)
    
    ; Tree 1: scrolled row 5, column 8
    cmp al, 5
    jne .checkLeftTree2
    cmp dl, 8
    je .drawLeftTree
    
.checkLeftTree2:           ; Tree 2: scrolled row 13, column 15
    cmp al, 13
    jne .checkLeftTree3
    cmp dl, 15
    je .drawLeftTree
    
.checkLeftTree3:           ; Tree 3: scrolled row 21, column 5
    cmp al, 21
    jne .checkLeftTree4
    cmp dl, 5
    je .drawLeftTree
    
.checkLeftTree4:           ; Tree 4: scrolled row 29, column 18
    cmp al, 29
    jne .normalLeft
    cmp dl, 18
    je .drawLeftTree
    
.normalLeft:
    mov ax, 0x2020         ; Green background, space character
    jmp .putLeft
    
.drawLeftTree:
    mov ax, 0x2006         ; Green background, brown tree symbol (♣)
    
.putLeft:
    mov [es:di], ax        ; Write to video memory
    inc dl                 ; Move to next column
    loop .leftTerrain      ; Repeat for all left terrain columns
    
    ; === Draw Road (30 columns) ===
    mov cx, ROAD_WIDTH
.roadLoop:
    call calcScreenPos
    
    ; Check if this column is a lane divider (columns 34-35 and 44-45)
    mov al, dl
    sub al, ROAD_LEFT      ; Get position relative to road start
    cmp al, 9              ; Lane divider 1
    je .checkDivider
    cmp al, 10
    je .checkDivider
    cmp al, 19             ; Lane divider 2
    je .checkDivider
    cmp al, 20
    je .checkDivider
    jmp .normalRoad
    
.checkDivider:
    ; Animate divider (creates dashed line effect)
    mov al, bl             ; Use scrolled row
    and al, 0x03           ; Pattern repeats every 4 rows
    cmp al, 0              ; Show divider for 2 rows
    je .drawDivider
    cmp al, 1
    je .drawDivider
    jmp .normalRoad        ; Hide divider for other 2 rows
    
.drawDivider:
    mov ax, 0x0F7C         ; White '|' character
    jmp .putRoad
    
.normalRoad:
    mov ax, 0x08B0         ; Gray shaded block (road surface)
    
.putRoad:
    mov [es:di], ax
    inc dl
    loop .roadLoop
    
    ; === Draw Right Terrain (25 columns) ===
    mov cx, SCREEN_WIDTH
    sub cx, ROAD_LEFT
    sub cx, ROAD_WIDTH     ; CX = remaining columns on right
.rightTerrain:
    call calcScreenPos
    
    ; Check for trees (4 trees on right side)
    mov al, bl
    and al, 0x1F
    
    ; Tree 5: scrolled row 3, column 60
    cmp al, 3
    jne .checkRightTree2
    cmp dl, 60
    je .drawRightTree
    
.checkRightTree2:          ; Tree 6: scrolled row 11, column 68
    cmp al, 11
    jne .checkRightTree3
    cmp dl, 68
    je .drawRightTree
    
.checkRightTree3:          ; Tree 7: scrolled row 19, column 58
    cmp al, 19
    jne .checkRightTree4
    cmp dl, 58
    je .drawRightTree
    
.checkRightTree4:          ; Tree 8: scrolled row 27, column 72
    cmp al, 27
    jne .normalRight
    cmp dl, 72
    je .drawRightTree
    
.normalRight:
    mov ax, 0x2020         ; Green grass
    jmp .putRight
    
.drawRightTree:
    mov ax, 0x2006         ; Brown tree
    
.putRight:
    mov [es:di], ax
    inc dl
    loop .rightTerrain
    
    inc dh                 ; Move to next row
    cmp dh, SCREEN_HEIGHT
    jl .rowLoop            ; Continue if more rows remain
    
    pop di                 ; Restore all registers
    pop dx
    pop cx
    pop bx
    pop ax
    pop es
    ret

; Draw Car - Renders player's car at bottom of screen
; Car stays in fixed vertical position, only moves horizontally
; No parameters (uses carLane variable)
; Modifies: ES, AX, BX, DX, DI
drawCar:
    push es                ; Save registers
    push ax
    push bx
    push dx
    push di
    
    mov ax, 0xb800         ; Video memory
    mov es, ax
    
    ; Calculate horizontal position based on lane
    mov al, [carLane]      ; Get current lane (0, 1, or 2)
    mov bl, LANE_WIDTH     ; BL = 10
    mul bl                 ; AX = lane * 10
    add al, ROAD_LEFT + 3  ; Add road offset + centering
    mov dl, al             ; DL = column position
    mov dh, SCREEN_HEIGHT - 3  ; DH = row 22 (near bottom)
    
    ; Draw car body (3 characters wide)
    call calcScreenPos
    mov ax, 0x0CDB         ; Red solid block █
    mov [es:di], ax        ; Draw left part
    mov [es:di+2], ax      ; Draw center part
    mov [es:di+4], ax      ; Draw right part
    
    ; Draw car front (row above, lighter color)
    dec dh                 ; Move to row above
    call calcScreenPos
    mov ax, 0x0CDF         ; Red lower block ▄
    mov [es:di], ax
    mov [es:di+2], ax
    mov [es:di+4], ax
    
    pop di                 ; Restore registers
    pop dx
    pop bx
    pop ax
    pop es
    ret

; Update Obstacles - Moves all enemy cars and bonuses down by one row
; Removes objects that go off bottom of screen
; No parameters
; Modifies: AX, BX, CX, SI
updateObstacles:
    push ax                ; Save registers
    push bx
    push cx
    push si
    
    ; === Update Enemy Cars ===
    xor ch, ch
    mov cl, [obstacleCount]  ; CL = number of obstacles
    test cl, cl              ; Check if any exist
    jz .updateBonus          ; If none, skip to bonuses
    
    xor si, si               ; SI = array index
    
.loop:
    mov al, [obstacleRows + si]  ; Get current row
    inc al                       ; Move down by 1
    cmp al, SCREEN_HEIGHT        ; Check if off screen
    jge .remove                  ; If yes, remove it
    
    mov [obstacleRows + si], al  ; Update position
    inc si                       ; Next obstacle
    loop .loop
    jmp .updateBonus
    
.remove:
    ; Clear lane occupation flag when obstacle leaves
    push si
    movzx bx, byte [obstacleLanes + si]  ; Get lane of this obstacle
    mov byte [laneOccupied + bx], 0      ; Mark lane as free
    pop si
    
    ; Shift remaining obstacles left in array (remove gap)
    push cx
    push si
    
.shiftLoop:
    mov al, [obstacleRows + si + 1]      ; Copy next obstacle's data
    mov [obstacleRows + si], al
    mov al, [obstacleLanes + si + 1]
    mov [obstacleLanes + si], al
    inc si
    loop .shiftLoop
    
    pop si
    pop cx
    dec byte [obstacleCount]  ; Decrease total count
    
.updateBonus:
    ; === Update Bonus Objects (same logic as obstacles) ===
    xor ch, ch
    mov cl, [bonusCount]
    test cl, cl
    jz .done
    
    xor si, si
    
.bonusLoop:
    mov al, [bonusRows + si]
    inc al
    cmp al, SCREEN_HEIGHT
    jge .removeBonus
    
    mov [bonusRows + si], al
    inc si
    loop .bonusLoop
    jmp .done
    
.removeBonus:
    push cx
    push si
    
.shiftBonusLoop:
    mov al, [bonusRows + si + 1]
    mov [bonusRows + si], al
    mov al, [bonusLanes + si + 1]
    mov [bonusLanes + si], al
    inc si
    loop .shiftBonusLoop
    
    pop si
    pop cx
    dec byte [bonusCount]
    
.done:
    pop si                 ; Restore registers
    pop cx
    pop bx
    pop ax
    ret

; Check Collision - Detects if player hits enemy or collects bonus
; No parameters
; Side effects: Sets gameRunning=0 on collision, increases score on bonus
checkCollision:
    push ax                ; Save registers
    push bx
    push cx
    push si
    
    mov al, SCREEN_HEIGHT - 3  ; Player car is at row 22
    xor ch, ch
    
    ; === Check Enemy Car Collisions ===
    mov cl, [obstacleCount]
    test cl, cl            ; Any obstacles?
    jz .checkBonus         ; If not, check bonuses
    
    xor si, si             ; Index = 0
    
.loop:
    mov ah, [obstacleRows + si]  ; Get obstacle row
    cmp al, ah                   ; Compare with car row
    jl .next                     ; If obstacle above car, no collision
    add ah, 2                    ; Obstacle is 2 rows tall
    cmp al, ah                   ; Check if car below obstacle
    jg .next                     ; If yes, no collision
    
    ; Rows overlap - check if lanes match
    mov al, [carLane]
    cmp al, [obstacleLanes + si]
    jne .next              ; Different lanes = no collision
    
    ; COLLISION DETECTED!
    mov byte [gameRunning], 0    ; End game
    jmp .done
    
.next:
    inc si                 ; Check next obstacle
    loop .loop
    
.checkBonus:
    ; === Check Bonus Collection ===
    mov cl, [bonusCount]
    test cl, cl
    jz .done
    
    xor si, si
    mov al, SCREEN_HEIGHT - 3
    
.bonusLoop:
    cmp al, [bonusRows + si]     ; Check if at same row
    jne .nextBonus
    
    mov al, [carLane]
    cmp al, [bonusLanes + si]    ; Check if at same lane
    jne .nextBonus
    
    ; BONUS COLLECTED!
    add word [score], 100        ; Increase score by 100
    
    ; Remove collected bonus from array
    push cx
    push si
    
.shiftBonusLoop:
    mov al, [bonusRows + si + 1]
    mov [bonusRows + si], al
    mov al, [bonusLanes + si + 1]
    mov [bonusLanes + si], al
    inc si
    loop .shiftBonusLoop
    
    pop si
    pop cx
    dec byte [bonusCount]
    jmp .done
    
.nextBonus:
    inc si
    loop .bonusLoop
    
.done:
    pop si                 ; Restore registers
    pop cx
    pop bx
    pop ax
    ret

; Spawn Obstacle - Creates new enemy cars and bonuses at top of screen
; Uses RTC for random lane selection
; Ensures max 2 out of 3 lanes occupied (always leaves escape route)
; No parameters
spawnObstacle:
    push ax                ; Save registers
    push bx
    push cx
    push dx
    push si
    
    ; === Count How Many Lanes Are Currently Occupied ===
    xor si, si
    xor bh, bh             ; BH = counter
    
.countLoop:
    mov al, [laneOccupied + si]
    add bh, al             ; Add 1 if lane occupied, 0 if free
    inc si
    cmp si, 3
    jl .countLoop
    
    ; If 2 lanes occupied, don't spawn more (keep 1 lane free)
    cmp bh, 2
    jge .tryBonus
    
    ; === Try to Spawn Enemy Car (80% chance) ===
    call getRandom         ; Get random number 0-59
    and al, 0x07           ; Reduce to 0-7
    cmp al, 6              ; If 7, skip (12.5% chance)
    jg .tryBonus
    
    ; Check if we've reached maximum enemies
    cmp byte [obstacleCount], 6
    jge .tryBonus
    
    ; === Select Random Lane ===
    call getRandom
    
    ; Convert to 0-2 using modulo 3 (repeated subtraction)
.mod3_obstacle:
    cmp al, 3
    jb .obstacle_lane_selected
    sub al, 3              ; Subtract 3 until less than 3
    jmp .mod3_obstacle
    
.obstacle_lane_selected:
    mov dl, al             ; DL = selected lane (0, 1, or 2)
    
    ; Check if selected lane is occupied
    movzx si, dl
    cmp byte [laneOccupied + si], 1
    jne .spawnObstacle
    
    ; If occupied, try next lane
    inc dl
    cmp dl, 3
    jb .check_next_obs
    mov dl, 0              ; Wrap around to lane 0
    
.check_next_obs:
    movzx si, dl
    cmp byte [laneOccupied + si], 1
    je .tryBonus           ; Both lanes full, skip spawning
    
.spawnObstacle:
    ; Add new obstacle to arrays
    movzx si, dl
    mov byte [laneOccupied + si], 1      ; Mark lane as occupied
    
    movzx bx, byte [obstacleCount]
    mov [obstacleLanes + bx], dl         ; Store lane
    mov byte [obstacleRows + bx], 0      ; Start at top (row 0)
    inc byte [obstacleCount]             ; Increase count
    
.tryBonus:
    ; === Try to Spawn Bonus ===
    inc byte [lastBonusSpawn]
    
    ; Only spawn bonus every 12 frames minimum (prevents clustering)
    cmp byte [lastBonusSpawn], 12
    jl .done
    
    ; 75% chance to spawn when eligible
    call getRandom
    and al, 0x03           ; Get 0-3
    cmp al, 3
    je .done               ; If 3, skip (25% chance)
    
    ; Check if we've reached maximum bonuses
    cmp byte [bonusCount], 3
    jge .done
    
    ; === Select Random Lane for Bonus ===
    call getRandom
    add al, 7              ; Offset by 7 for variety (different from obstacles)
    
.mod3_bonus:
    cmp al, 3
    jb .bonus_lane_selected
    sub al, 3
    jmp .mod3_bonus
    
.bonus_lane_selected:
    mov dl, al             ; DL = lane
    
    ; Add bonus to arrays
    movzx bx, byte [bonusCount]
    mov [bonusLanes + bx], dl
    mov byte [bonusRows + bx], 0
    inc byte [bonusCount]
    
    mov byte [lastBonusSpawn], 0  ; Reset spawn timer
    
.done:
    pop si                 ; Restore registers
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Draw Obstacles - Renders all enemy cars and bonuses on screen
; No parameters
drawObstacles:
    push es                ; Save registers
    push ax
    push bx
    push cx
    push dx
    push di
    push si
    
    mov ax, 0xb800         ; Video memory
    mov es, ax
    
    ; === Draw Enemy Cars ===
    xor ch, ch
    mov cl, [obstacleCount]
    test cl, cl            ; Any obstacles?
    jz .drawBonus          ; If not, skip to bonuses
    
    xor si, si             ; Index = 0
    
.loop:
    mov dh, [obstacleRows + si]  ; Get row
    
    ; Calculate column position
    mov al, [obstacleLanes + si] ; Get lane
    mov bl, LANE_WIDTH
    mul bl                       ; Lane * 10
    add al, ROAD_LEFT + 3
    mov dl, al                   ; DL = column
    
    ; Draw enemy car (3 chars wide, 2 rows tall)
    call calcScreenPos
    mov ax, 0x09DB         ; Blue solid block
    mov [es:di], ax        ; Left
    mov [es:di+2], ax      ; Center
    mov [es:di+4], ax      ; Right
    
    ; Draw second row
    inc dh
    call calcScreenPos
    mov ax, 0x09DB
    mov [es:di], ax
    mov [es:di+2], ax
    mov [es:di+4], ax
    
    inc si                 ; Next obstacle
    loop .loop
    
.drawBonus:
    ; === Draw Bonus Objects ===
    xor ch, ch
    mov cl, [bonusCount]
    test cl, cl
    jz .done
    
    xor si, si
    
.bonusLoop:
    mov dh, [bonusRows + si]
    
    ; Calculate column
    mov al, [bonusLanes + si]
    mov bl, LANE_WIDTH
    mul bl
    add al, ROAD_LEFT + 4
    mov dl, al
    
    call calcScreenPos
    mov ax, 0x0E24         ; Yellow '$' symbol
    mov [es:di], ax
    
    inc si
    loop .bonusLoop
    
.done:
    pop si                 ; Restore registers
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    pop es
    ret

; ====== MAIN PROGRAM ==========


start:
;setting the screen up
    call clrscr            ; Clear screen (fill with green)
    call drawScreen        ; Draw road, terrain, trees
    call drawCar           ; Draw player's car
    
    ; Display initial score
    push 0                 ; Row 0
    push 60                ; Column 60
    push msgScore
    call printstr
    
    push 0
    push 67
    push word [score]
    call printnum

; === Main Game Loop ===
gameLoop:
   
    mov ah, 1              ; BIOS function: check keyboard status
    int 0x16               ; INT 16h - keyboard services
    jnz .keyPressed        ; ZF=0 means key is available
    jmp .updateGame        ; No key, continue game
    
.keyPressed:
    ; Get the key that was pressed
    mov ah, 0              ; BIOS function: read keyboard
    int 0x16               ; Returns: AH=scan code, AL=ASCII
    
    ; === Process Arrow Keys ===
    ; Left arrow (scan code 4Bh)
    cmp ah, 0x4B
    jne .checkRight
    cmp byte [carLane], 0  ; Already at leftmost lane?
    je .updateGame
    dec byte [carLane]     ; Move left
    jmp .updateGame
    
.checkRight:
    ; Right arrow (scan code 4Dh)
    cmp ah, 0x4D
    jne .checkEsc
    cmp byte [carLane], 2  ; Already at rightmost lane?
    je .updateGame
    inc byte [carLane]     ; Move right
    jmp .updateGame
    
.checkEsc:
    ; ESC key to quit (scan code 01h)
    cmp ah, 0x01
    jne .updateGame
    jmp gameOver           ; Exit game
    
.updateGame:
    ; === control game speed ===
    ; increment counter and only update every 6 iterations much slower scroll
    inc byte [scrollCounter]
    cmp byte [scrollCounter], 6  ; update every 6th loop iterationsz
    jl gameLoop            ; if less than 6, loop again without updating
    
    mov byte [scrollCounter], 0  ; Reset counter
    inc byte [scrollOffset]      ; Increment scroll offset (moves screen down)
    
    ; === Update Score Slowly ===
    ; Increment score every 5 frames (not every frame)
    inc byte [scoreCounter]
    cmp byte [scoreCounter], 5
    jl .skipScore
    mov byte [scoreCounter], 0
    inc word [score]       ; Add 1 to score
    
.skipScore:
    ; === Update Game Objects ===
    call updateObstacles   ; Move all enemies and bonuses down
    call spawnObstacle     ; Try to create new enemies/bonuses
    call checkCollision    ; Check if player hit enemy or collected bonus
    
    ; Check if collision occurred
    cmp byte [gameRunning], 0
    je gameOver            ; If 0, game over
    
    ; === Redraw Everything ===
    call drawScreen        ; Redraw scrolling background
    call drawObstacles     ; Draw all enemies and bonuses
    call drawCar           ; Draw player car
    
    ; Update score display
    push 0
    push 60
    push msgScore
    call printstr
    
    push 0
    push 67
    push word [score]
    call printnum
    
    jmp gameLoop           ; Continue game loop

; === Game Over Screen ===
gameOver:
    call clrscr            ; Clear screen
    
    ; Display "GAME OVER!" message
    push 10                ; Row 10 (centered vertically)
    push 35                ; Column 35 (centered horizontally)
    push msgGameOver
    call printstr
    
    ; Display "Final Score: " label
    push 15                ; Row 15
    push 32
    push msgFinalScore
    call printstr
    
    ; Display the actual score number
    push 15
    push 47                ; Position right after "Final Score: "
    push word [score]
    call printnum
    
    ; Wait for any key press before exiting
    mov ah, 0
    int 0x16
    

    mov ax, 0x4c00         

    int 0x21               




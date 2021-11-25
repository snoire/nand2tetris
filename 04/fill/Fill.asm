// This file is part of www.nand2tetris.org
// and the book "The Elements of Computing Systems"
// by Nisan and Schocken, MIT Press.
// File name: projects/04/Fill.asm

// Runs an infinite loop that listens to the keyboard input.
// When a key is pressed (any key), the program blackens the screen,
// i.e. writes "black" in every pixel;
// the screen should remain fully black as long as the key is pressed. 
// When no key is pressed, the program clears the screen, i.e. writes
// "white" in every pixel;
// the screen should remain fully clear as long as no key is pressed.

//prestate=1 // unknown
//LOOP:
//    if (KBD > 0)
//      curstate=-1; // a key is pressed
//    else
//      curstate=0;  // no key is pressed
//
//    if (curstate == prestate)
//        jmp END
//
//    // fill or clear the screen
//    @curstate
//    D=M
//    @SCREEN
//    M=D
//    // loop ..
//
//END:
//    prestate=curstate;
//    jmp LOOP

    @prestate
    M=1

(LOOP)
    // curstate = 0;
    @curstate
    M=0
    // curstate = -1 if KBD > 0
    @KBD
    D=M
    @NOKEY
    D;JEQ
    @curstate
    M=-1
(NOKEY)

    // goto END if (curstate == prestate)
    @curstate
    D=M
    @prestate
    D=D-M
    @END
    D;JEQ

// fill or clear the screen (depends on the curstate)
    // R0 = SCREEN
    @SCREEN
    D=A
    @R0
    M=D
    // R1 = SCREEN + MAX - 1
    @KBD
    D=A-1
    @R1
    M=D

(FILL)
    // fill or clear the screen
    @curstate
    D=M
    @R1
    A=M // use R1 as a pointer
    M=D

    // R1--
    @R1
    M=M-1
    // if (R1 >= R0) goto FILL
    D=M
    @R0
    D=D-M
    @FILL
    D;JGE

(END)
    // prestate = curstate;
    @curstate
    D=M
    @prestate
    M=D

    // jmp LOOP
    @LOOP
    0;JMP
# Zig80

A fast [z80][z80] cpu emulator written in [Zig][Zig], implementing both documented and undocumented behaviors. This emulator is not cycle-accurate but instruction-stepped. So the cycles are counted at an instruction level.

## Usage

> [!NOTE]
> Zig `0.16.0` or later is required

Add the `zig80` package to your `build.zig.zon`:

```
zig fetch --save git+https://github.com/Frost-Phoenix/zig80.git
```

You can then import `zig80` in your `build.zig` with:

```zig
const zig80 = b.dependency("zig80", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zig80", zig80.module("zig80"));
```

For usage examples, you can take a look at the test runners in `./tests/`:
- [sst.zig](./tests/sst.zig)
- [zex.zig](./tests/zex.zig)
- [z80test.zig](./tests/z80test.zig)

## Tests

The project has a dedicated test runner `zig80_test`. It is used to test the z80 core against three different test suites:

- **sst**: JSON-based single-step tests that verify each instruction individually.
- **zex**: The Z80 instruction set exerciser, covering the full instruction set.
- **z80test**: The Zilog Z80 CPU test suite, checking documented and undocumented behaviors.

To compile and run the test runner you can use the following:

```
zig build test --release=fast
```

Note that compiling with optimizations enabled is not necessary. But the tests will run from 5 to 10 times slower in debug mode.

Below is the usage of the test runner, along with all test outputs.

```
Usage: zig80_test <command> [options]

Commands:
    sst         Run the Json Single Step Tests
    zex         Run the Z80 instruction set exerciser test suite
    z80test     Run the Zilog Z80 CPU test suite

sst options:
    -s, --summary
        Only show the test summary
    -r, --run <file>
        Run the specified opcode test file

zex options:
    -r, --run <zexall|zexdoc|prelim>
        Run the specified test rom

z80test options:
    -r, --run <ccf|doc|docflags|flags|full|memptr>
        Run the specified test rom

Global options:
    -h, --help
        Show this help message
```

### Single Step Tests

```
Z80 Single Step Tests

Summary
├─ Ran 1604 tests
│  ├─ Passed        1604/1604
│  ├─ Skipped          0/1604
│  └─ Failed           0/1604
└─ Detail
   ├─ Main            252/252
   ├─ (ED) Misc        80/ 80
   ├─ (CB) Bit        256/256
   ├─ (DD) IX         252/252
   ├─ (FD) IY         252/252
   ├─ (DDCB) IX Bit   256/256
   └─ (FDCB) IY Bit   256/256
```

### Z80 Instruction Set Exerciser

| Test   | Result |
| ------ | :----: |
| prelim |  PASS  |
| zexdoc |  PASS  |
| zexall |  PASS  |

<!-- prelim output -->
<details>
<summary>prelim output</summary>

```
Z80 ZEX Tests

info: Running prelim.com

Preliminary tests complete

info: Test prelim.com took 8703 cycles, and ran in 0.00s
info: Test prelim.com ran at 231.89 MHz (23.93 MIPS)
```
</details>

<!-- zexdoc output -->
<details>
<summary>zexdoc output</summary>

```
Z80 ZEX Tests

info: Running zexdoc.com

Z80 instruction exerciser
<adc,sbc> hl,<bc,de,hl,sp>....  OK
add hl,<bc,de,hl,sp>..........  OK
add ix,<bc,de,ix,sp>..........  OK
add iy,<bc,de,iy,sp>..........  OK
aluop a,nn....................  OK
aluop a,<b,c,d,e,h,l,(hl),a>..  OK
aluop a,<ixh,ixl,iyh,iyl>.....  OK
aluop a,(<ix,iy>+1)...........  OK
bit n,(<ix,iy>+1).............  OK
bit n,<b,c,d,e,h,l,(hl),a>....  OK
cpd<r>........................  OK
cpi<r>........................  OK
<daa,cpl,scf,ccf>.............  OK
<inc,dec> a...................  OK
<inc,dec> b...................  OK
<inc,dec> bc..................  OK
<inc,dec> c...................  OK
<inc,dec> d...................  OK
<inc,dec> de..................  OK
<inc,dec> e...................  OK
<inc,dec> h...................  OK
<inc,dec> hl..................  OK
<inc,dec> ix..................  OK
<inc,dec> iy..................  OK
<inc,dec> l...................  OK
<inc,dec> (hl)................  OK
<inc,dec> sp..................  OK
<inc,dec> (<ix,iy>+1).........  OK
<inc,dec> ixh.................  OK
<inc,dec> ixl.................  OK
<inc,dec> iyh.................  OK
<inc,dec> iyl.................  OK
ld <bc,de>,(nnnn).............  OK
ld hl,(nnnn)..................  OK
ld sp,(nnnn)..................  OK
ld <ix,iy>,(nnnn).............  OK
ld (nnnn),<bc,de>.............  OK
ld (nnnn),hl..................  OK
ld (nnnn),sp..................  OK
ld (nnnn),<ix,iy>.............  OK
ld <bc,de,hl,sp>,nnnn.........  OK
ld <ix,iy>,nnnn...............  OK
ld a,<(bc),(de)>..............  OK
ld <b,c,d,e,h,l,(hl),a>,nn....  OK
ld (<ix,iy>+1),nn.............  OK
ld <b,c,d,e>,(<ix,iy>+1)......  OK
ld <h,l>,(<ix,iy>+1)..........  OK
ld a,(<ix,iy>+1)..............  OK
ld <ixh,ixl,iyh,iyl>,nn.......  OK
ld <bcdehla>,<bcdehla>........  OK
ld <bcdexya>,<bcdexya>........  OK
ld a,(nnnn) / ld (nnnn),a.....  OK
ldd<r> (1)....................  OK
ldd<r> (2)....................  OK
ldi<r> (1)....................  OK
ldi<r> (2)....................  OK
neg...........................  OK
<rrd,rld>.....................  OK
<rlca,rrca,rla,rra>...........  OK
shf/rot (<ix,iy>+1)...........  OK
shf/rot <b,c,d,e,h,l,(hl),a>..  OK
<set,res> n,<bcdehl(hl)a>.....  OK
<set,res> n,(<ix,iy>+1).......  OK
ld (<ix,iy>+1),<b,c,d,e>......  OK
ld (<ix,iy>+1),<h,l>..........  OK
ld (<ix,iy>+1),a..............  OK
ld (<bc,de>),a................  OK
Tests complete

info: Test zexdoc.com took 46734977146 cycles, and ran in 22.53s
info: Test zexdoc.com ran at 2074.74 MHz (255.89 MIPS)
```
</details>

<!-- zexall output -->
<details>
<summary>zexall output</summary>

```
Z80 ZEX Tests

info: Running zexall.com

Z80 instruction exerciser
<adc,sbc> hl,<bc,de,hl,sp>....  OK
add hl,<bc,de,hl,sp>..........  OK
add ix,<bc,de,ix,sp>..........  OK
add iy,<bc,de,iy,sp>..........  OK
aluop a,nn....................  OK
aluop a,<b,c,d,e,h,l,(hl),a>..  OK
aluop a,<ixh,ixl,iyh,iyl>.....  OK
aluop a,(<ix,iy>+1)...........  OK
bit n,(<ix,iy>+1).............  OK
bit n,<b,c,d,e,h,l,(hl),a>....  OK
cpd<r>........................  OK
cpi<r>........................  OK
<daa,cpl,scf,ccf>.............  OK
<inc,dec> a...................  OK
<inc,dec> b...................  OK
<inc,dec> bc..................  OK
<inc,dec> c...................  OK
<inc,dec> d...................  OK
<inc,dec> de..................  OK
<inc,dec> e...................  OK
<inc,dec> h...................  OK
<inc,dec> hl..................  OK
<inc,dec> ix..................  OK
<inc,dec> iy..................  OK
<inc,dec> l...................  OK
<inc,dec> (hl)................  OK
<inc,dec> sp..................  OK
<inc,dec> (<ix,iy>+1).........  OK
<inc,dec> ixh.................  OK
<inc,dec> ixl.................  OK
<inc,dec> iyh.................  OK
<inc,dec> iyl.................  OK
ld <bc,de>,(nnnn).............  OK
ld hl,(nnnn)..................  OK
ld sp,(nnnn)..................  OK
ld <ix,iy>,(nnnn).............  OK
ld (nnnn),<bc,de>.............  OK
ld (nnnn),hl..................  OK
ld (nnnn),sp..................  OK
ld (nnnn),<ix,iy>.............  OK
ld <bc,de,hl,sp>,nnnn.........  OK
ld <ix,iy>,nnnn...............  OK
ld a,<(bc),(de)>..............  OK
ld <b,c,d,e,h,l,(hl),a>,nn....  OK
ld (<ix,iy>+1),nn.............  OK
ld <b,c,d,e>,(<ix,iy>+1)......  OK
ld <h,l>,(<ix,iy>+1)..........  OK
ld a,(<ix,iy>+1)..............  OK
ld <ixh,ixl,iyh,iyl>,nn.......  OK
ld <bcdehla>,<bcdehla>........  OK
ld <bcdexya>,<bcdexya>........  OK
ld a,(nnnn) / ld (nnnn),a.....  OK
ldd<r> (1)....................  OK
ldd<r> (2)....................  OK
ldi<r> (1)....................  OK
ldi<r> (2)....................  OK
neg...........................  OK
<rrd,rld>.....................  OK
<rlca,rrca,rla,rra>...........  OK
shf/rot (<ix,iy>+1)...........  OK
shf/rot <b,c,d,e,h,l,(hl),a>..  OK
<set,res> n,<bcdehl(hl)a>.....  OK
<set,res> n,(<ix,iy>+1).......  OK
ld (<ix,iy>+1),<b,c,d,e>......  OK
ld (<ix,iy>+1),<h,l>..........  OK
ld (<ix,iy>+1),a..............  OK
ld (<bc,de>),a................  OK
Tests complete

info: Test zexall.com took 46734977146 cycles, and ran in 22.62s
info: Test zexall.com ran at 2065.98 MHz (254.81 MIPS)
```
</details>

### Zilog Z80 CPU Test Suite

| Test        | Result |
| ----------- | :----: |
| z80doc      |  PASS  |
| z80full     |  PASS  |
| z80docflags |  PASS  |
| z80flags    |  PASS  |
| z80memptr   |  PASS  |
| z80ccf      |  PASS  |

<!-- z80doc output -->
<details>
<summary>z80doc output</summary>

```
Z80 z80test Tests

info: Running z80doc.tap

Z80 doc test  2012 RAXOFT

000 SELF TEST OK
001 SCF OK
002 CCF OK
003 SCF (NEC) Skipped
004 CCF (NEC) Skipped
005 SCF (ST) Skipped
006 CCF (ST) Skipped
007 SCF+CCF OK
008 CCF+SCF OK
009 DAA OK
010 CPL OK
011 NEG OK
012 NEG' OK
013 ADD A,N OK
014 ADC A,N OK
015 SUB A,N OK
016 SBC A,N OK
017 AND N OK
018 XOR N OK
019 OR N OK
020 CP N OK
021 ALO A,A OK
022 ALO A,[B,C] OK
023 ALO A,[D,E] OK
024 ALO A,[H,L] OK
025 ALO A,(HL) OK
026 ALO A,[HX,LX] OK
027 ALO A,[HY,LY] OK
028 ALO A,(XY) OK
029 RLCA OK
030 RRCA OK
031 RLA OK
032 RRA OK
033 RLD OK
034 RRD OK
035 RLC A OK
036 RRC A OK
037 RL A OK
038 RR A OK
039 SLA A OK
040 SRA A OK
041 SLIA A OK
042 SRL A OK
043 RLC [R,(HL)] OK
044 RRC [R,(HL)] OK
045 RL [R,(HL)] OK
046 RR [R,(HL)] OK
047 SLA [R,(HL)] OK
048 SRA [R,(HL)] OK
049 SLIA [R,(HL)] OK
050 SRL [R,(HL)] OK
051 SRO (XY) OK
052 SRO (XY),R OK
053 INC A OK
054 DEC A OK
055 INC [R,(HL)] OK
056 DEC [R,(HL)] OK
057 INC X OK
058 DEC X OK
059 INC (XY) OK
060 DEC (XY) OK
061 INC RR OK
062 DEC RR OK
063 INC XY OK
064 DEC XY OK
065 ADD HL,RR OK
066 ADD IX,RR OK
067 ADD IY,RR OK
068 ADC HL,RR OK
069 SBC HL,RR OK
070 BIT N,A OK
071 BIT N,(HL) OK
072 BIT N,[R,(HL)] OK
073 BIT N,(XY) OK
074 BIT N,(XY),- OK
075 SET N,A OK
076 SET N,(HL) OK
077 SET N,[R,(HL)] OK
078 SET N,(XY) OK
079 SET N,(XY),R OK
080 RES N,A OK
081 RES N,(HL) OK
082 RES N,[R,(HL)] OK
083 RES N,(XY) OK
084 RES N,(XY),R OK
085 LDI OK
086 LDD OK
087 LDIR OK
088 LDDR OK
089 LDIR->NOP' OK
090 LDDR->NOP' OK
091 CPI OK
092 CPD OK
093 CPIR OK
094 CPDR OK
095 IN A,(N) OK
096 IN R,(C) OK
097 IN (C) OK
098 INI OK
099 IND OK
100 INIR OK
101 INDR OK
102 INIR->NOP' OK
103 INDR->NOP' OK
104 OUT (N),A OK
105 OUT (C),R OK
106 OUT (C),0 OK
107 OUTI OK
108 OUTD OK
109 OTIR OK
110 OTDR OK
111 JP NN OK
112 JP CC,NN OK
113 JP (HL) OK
114 JP (XY) OK
115 JR N OK
116 JR CC,N OK
117 DJNZ N OK
118 CALL NN OK
119 CALL CC,NN OK
120 RET OK
121 RET CC OK
122 RETN OK
123 RETI OK
124 RETI/RETN OK
125 PUSH+POP RR OK
126 POP+PUSH AF OK
127 PUSH+POP XY OK
128 EX DE,HL OK
129 EX AF,AF' OK
130 EXX OK
131 EX (SP),HL OK
132 EX (SP),XY OK
133 LD [R,(HL)],[R,(HL)] OK
134 LD [X,(XY)],[X,(XY)] OK
135 LD R,(XY) OK
136 LD (XY),R OK
137 LD [R,(HL)],N OK
138 LD X,N OK
139 LD (XY),N OK
140 LD A,([BC,DE]) OK
141 LD ([BC,DE]),A OK
142 LD A,(NN) OK
143 LD (NN),A OK
144 LD RR,NN OK
145 LD XY,NN OK
146 LD HL,(NN) OK
147 LD XY,(NN) OK
148 LD RR,(NN) OK
149 LD (NN),HL OK
150 LD (NN),XY OK
151 LD (NN),RR OK
152 LD SP,HL OK
153 LD SP,XY OK
154 LD I,A OK
155 LD R,A OK
156 LD A,I OK
157 LD A,R OK
158 EI+DI OK
159 IM N OK

Result: all tests passed.

info: Test doc.tap took 1139700409 cycles, and ran in 0.82s
info: Test doc.tap ran at 1387.49 MHz (230.19 MIPS)
```
</details>

<!-- z80full output -->
<details>
<summary>z80full output</summary>

```
Z80 z80test Tests

info: Running z80full.tap

Z80 full test  2012 RAXOFT

000 SELF TEST OK
001 SCF OK
002 CCF OK
003 SCF (NEC) Skipped
004 CCF (NEC) Skipped
005 SCF (ST) Skipped
006 CCF (ST) Skipped
007 SCF+CCF OK
008 CCF+SCF OK
009 DAA OK
010 CPL OK
011 NEG OK
012 NEG' OK
013 ADD A,N OK
014 ADC A,N OK
015 SUB A,N OK
016 SBC A,N OK
017 AND N OK
018 XOR N OK
019 OR N OK
020 CP N OK
021 ALO A,A OK
022 ALO A,[B,C] OK
023 ALO A,[D,E] OK
024 ALO A,[H,L] OK
025 ALO A,(HL) OK
026 ALO A,[HX,LX] OK
027 ALO A,[HY,LY] OK
028 ALO A,(XY) OK
029 RLCA OK
030 RRCA OK
031 RLA OK
032 RRA OK
033 RLD OK
034 RRD OK
035 RLC A OK
036 RRC A OK
037 RL A OK
038 RR A OK
039 SLA A OK
040 SRA A OK
041 SLIA A OK
042 SRL A OK
043 RLC [R,(HL)] OK
044 RRC [R,(HL)] OK
045 RL [R,(HL)] OK
046 RR [R,(HL)] OK
047 SLA [R,(HL)] OK
048 SRA [R,(HL)] OK
049 SLIA [R,(HL)] OK
050 SRL [R,(HL)] OK
051 SRO (XY) OK
052 SRO (XY),R OK
053 INC A OK
054 DEC A OK
055 INC [R,(HL)] OK
056 DEC [R,(HL)] OK
057 INC X OK
058 DEC X OK
059 INC (XY) OK
060 DEC (XY) OK
061 INC RR OK
062 DEC RR OK
063 INC XY OK
064 DEC XY OK
065 ADD HL,RR OK
066 ADD IX,RR OK
067 ADD IY,RR OK
068 ADC HL,RR OK
069 SBC HL,RR OK
070 BIT N,A OK
071 BIT N,(HL) OK
072 BIT N,[R,(HL)] OK
073 BIT N,(XY) OK
074 BIT N,(XY),- OK
075 SET N,A OK
076 SET N,(HL) OK
077 SET N,[R,(HL)] OK
078 SET N,(XY) OK
079 SET N,(XY),R OK
080 RES N,A OK
081 RES N,(HL) OK
082 RES N,[R,(HL)] OK
083 RES N,(XY) OK
084 RES N,(XY),R OK
085 LDI OK
086 LDD OK
087 LDIR OK
088 LDDR OK
089 LDIR->NOP' OK
090 LDDR->NOP' OK
091 CPI OK
092 CPD OK
093 CPIR OK
094 CPDR OK
095 IN A,(N) OK
096 IN R,(C) OK
097 IN (C) OK
098 INI OK
099 IND OK
100 INIR OK
101 INDR OK
102 INIR->NOP' OK
103 INDR->NOP' OK
104 OUT (N),A OK
105 OUT (C),R OK
106 OUT (C),0 OK
107 OUTI OK
108 OUTD OK
109 OTIR OK
110 OTDR OK
111 JP NN OK
112 JP CC,NN OK
113 JP (HL) OK
114 JP (XY) OK
115 JR N OK
116 JR CC,N OK
117 DJNZ N OK
118 CALL NN OK
119 CALL CC,NN OK
120 RET OK
121 RET CC OK
122 RETN OK
123 RETI OK
124 RETI/RETN OK
125 PUSH+POP RR OK
126 POP+PUSH AF OK
127 PUSH+POP XY OK
128 EX DE,HL OK
129 EX AF,AF' OK
130 EXX OK
131 EX (SP),HL OK
132 EX (SP),XY OK
133 LD [R,(HL)],[R,(HL)] OK
134 LD [X,(XY)],[X,(XY)] OK
135 LD R,(XY) OK
136 LD (XY),R OK
137 LD [R,(HL)],N OK
138 LD X,N OK
139 LD (XY),N OK
140 LD A,([BC,DE]) OK
141 LD ([BC,DE]),A OK
142 LD A,(NN) OK
143 LD (NN),A OK
144 LD RR,NN OK
145 LD XY,NN OK
146 LD HL,(NN) OK
147 LD XY,(NN) OK
148 LD RR,(NN) OK
149 LD (NN),HL OK
150 LD (NN),XY OK
151 LD (NN),RR OK
152 LD SP,HL OK
153 LD SP,XY OK
154 LD I,A OK
155 LD R,A OK
156 LD A,I OK
157 LD A,R OK
158 EI+DI OK
159 IM N OK

Result: all tests passed.

info: Test full.tap took 1132649557 cycles, and ran in 0.84s
info: Test full.tap ran at 1356.07 MHz (225.17 MIPS)
```
</details>

<!-- z80docflags output -->
<details>
<summary>z80docflags output</summary>

```
Z80 z80test Tests

info: Running z80docflags.tap

Z80 doc flags test  2012 RAXOFT

000 SELF TEST OK
001 SCF OK
002 CCF OK
003 SCF (NEC) Skipped
004 CCF (NEC) Skipped
005 SCF (ST) Skipped
006 CCF (ST) Skipped
007 SCF+CCF OK
008 CCF+SCF OK
009 DAA OK
010 CPL OK
011 NEG OK
012 NEG' OK
013 ADD A,N OK
014 ADC A,N OK
015 SUB A,N OK
016 SBC A,N OK
017 AND N OK
018 XOR N OK
019 OR N OK
020 CP N OK
021 ALO A,A OK
022 ALO A,[B,C] OK
023 ALO A,[D,E] OK
024 ALO A,[H,L] OK
025 ALO A,(HL) OK
026 ALO A,[HX,LX] OK
027 ALO A,[HY,LY] OK
028 ALO A,(XY) OK
029 RLCA OK
030 RRCA OK
031 RLA OK
032 RRA OK
033 RLD OK
034 RRD OK
035 RLC A OK
036 RRC A OK
037 RL A OK
038 RR A OK
039 SLA A OK
040 SRA A OK
041 SLIA A OK
042 SRL A OK
043 RLC [R,(HL)] OK
044 RRC [R,(HL)] OK
045 RL [R,(HL)] OK
046 RR [R,(HL)] OK
047 SLA [R,(HL)] OK
048 SRA [R,(HL)] OK
049 SLIA [R,(HL)] OK
050 SRL [R,(HL)] OK
051 SRO (XY) OK
052 SRO (XY),R OK
053 INC A OK
054 DEC A OK
055 INC [R,(HL)] OK
056 DEC [R,(HL)] OK
057 INC X OK
058 DEC X OK
059 INC (XY) OK
060 DEC (XY) OK
061 INC RR OK
062 DEC RR OK
063 INC XY OK
064 DEC XY OK
065 ADD HL,RR OK
066 ADD IX,RR OK
067 ADD IY,RR OK
068 ADC HL,RR OK
069 SBC HL,RR OK
070 BIT N,A OK
071 BIT N,(HL) OK
072 BIT N,[R,(HL)] OK
073 BIT N,(XY) OK
074 BIT N,(XY),- OK
075 SET N,A OK
076 SET N,(HL) OK
077 SET N,[R,(HL)] OK
078 SET N,(XY) OK
079 SET N,(XY),R OK
080 RES N,A OK
081 RES N,(HL) OK
082 RES N,[R,(HL)] OK
083 RES N,(XY) OK
084 RES N,(XY),R OK
085 LDI OK
086 LDD OK
087 LDIR OK
088 LDDR OK
089 LDIR->NOP' OK
090 LDDR->NOP' OK
091 CPI OK
092 CPD OK
093 CPIR OK
094 CPDR OK
095 IN A,(N) OK
096 IN R,(C) OK
097 IN (C) OK
098 INI OK
099 IND OK
100 INIR OK
101 INDR OK
102 INIR->NOP' OK
103 INDR->NOP' OK
104 OUT (N),A OK
105 OUT (C),R OK
106 OUT (C),0 OK
107 OUTI OK
108 OUTD OK
109 OTIR OK
110 OTDR OK
111 JP NN OK
112 JP CC,NN OK
113 JP (HL) OK
114 JP (XY) OK
115 JR N OK
116 JR CC,N OK
117 DJNZ N OK
118 CALL NN OK
119 CALL CC,NN OK
120 RET OK
121 RET CC OK
122 RETN OK
123 RETI OK
124 RETI/RETN OK
125 PUSH+POP RR OK
126 POP+PUSH AF OK
127 PUSH+POP XY OK
128 EX DE,HL OK
129 EX AF,AF' OK
130 EXX OK
131 EX (SP),HL OK
132 EX (SP),XY OK
133 LD [R,(HL)],[R,(HL)] OK
134 LD [X,(XY)],[X,(XY)] OK
135 LD R,(XY) OK
136 LD (XY),R OK
137 LD [R,(HL)],N OK
138 LD X,N OK
139 LD (XY),N OK
140 LD A,([BC,DE]) OK
141 LD ([BC,DE]),A OK
142 LD A,(NN) OK
143 LD (NN),A OK
144 LD RR,NN OK
145 LD XY,NN OK
146 LD HL,(NN) OK
147 LD XY,(NN) OK
148 LD RR,(NN) OK
149 LD (NN),HL OK
150 LD (NN),XY OK
151 LD (NN),RR OK
152 LD SP,HL OK
153 LD SP,XY OK
154 LD I,A OK
155 LD R,A OK
156 LD A,I OK
157 LD A,R OK
158 EI+DI OK
159 IM N OK

Result: all tests passed.

info: Test docflags.tap took 559087557 cycles, and ran in 0.40s
info: Test docflags.tap ran at 1397.97 MHz (204.24 MIPS)
```
</details>

<!-- z80flags output -->
<details>
<summary>z80flags output</summary>

```
Z80 z80test Tests

info: Running z80flags.tap

Z80 flags test  2012 RAXOFT

000 SELF TEST OK
001 SCF OK
002 CCF OK
003 SCF (NEC) Skipped
004 CCF (NEC) Skipped
005 SCF (ST) Skipped
006 CCF (ST) Skipped
007 SCF+CCF OK
008 CCF+SCF OK
009 DAA OK
010 CPL OK
011 NEG OK
012 NEG' OK
013 ADD A,N OK
014 ADC A,N OK
015 SUB A,N OK
016 SBC A,N OK
017 AND N OK
018 XOR N OK
019 OR N OK
020 CP N OK
021 ALO A,A OK
022 ALO A,[B,C] OK
023 ALO A,[D,E] OK
024 ALO A,[H,L] OK
025 ALO A,(HL) OK
026 ALO A,[HX,LX] OK
027 ALO A,[HY,LY] OK
028 ALO A,(XY) OK
029 RLCA OK
030 RRCA OK
031 RLA OK
032 RRA OK
033 RLD OK
034 RRD OK
035 RLC A OK
036 RRC A OK
037 RL A OK
038 RR A OK
039 SLA A OK
040 SRA A OK
041 SLIA A OK
042 SRL A OK
043 RLC [R,(HL)] OK
044 RRC [R,(HL)] OK
045 RL [R,(HL)] OK
046 RR [R,(HL)] OK
047 SLA [R,(HL)] OK
048 SRA [R,(HL)] OK
049 SLIA [R,(HL)] OK
050 SRL [R,(HL)] OK
051 SRO (XY) OK
052 SRO (XY),R OK
053 INC A OK
054 DEC A OK
055 INC [R,(HL)] OK
056 DEC [R,(HL)] OK
057 INC X OK
058 DEC X OK
059 INC (XY) OK
060 DEC (XY) OK
061 INC RR OK
062 DEC RR OK
063 INC XY OK
064 DEC XY OK
065 ADD HL,RR OK
066 ADD IX,RR OK
067 ADD IY,RR OK
068 ADC HL,RR OK
069 SBC HL,RR OK
070 BIT N,A OK
071 BIT N,(HL) OK
072 BIT N,[R,(HL)] OK
073 BIT N,(XY) OK
074 BIT N,(XY),- OK
075 SET N,A OK
076 SET N,(HL) OK
077 SET N,[R,(HL)] OK
078 SET N,(XY) OK
079 SET N,(XY),R OK
080 RES N,A OK
081 RES N,(HL) OK
082 RES N,[R,(HL)] OK
083 RES N,(XY) OK
084 RES N,(XY),R OK
085 LDI OK
086 LDD OK
087 LDIR OK
088 LDDR OK
089 LDIR->NOP' OK
090 LDDR->NOP' OK
091 CPI OK
092 CPD OK
093 CPIR OK
094 CPDR OK
095 IN A,(N) OK
096 IN R,(C) OK
097 IN (C) OK
098 INI OK
099 IND OK
100 INIR OK
101 INDR OK
102 INIR->NOP' OK
103 INDR->NOP' OK
104 OUT (N),A OK
105 OUT (C),R OK
106 OUT (C),0 OK
107 OUTI OK
108 OUTD OK
109 OTIR OK
110 OTDR OK
111 JP NN OK
112 JP CC,NN OK
113 JP (HL) OK
114 JP (XY) OK
115 JR N OK
116 JR CC,N OK
117 DJNZ N OK
118 CALL NN OK
119 CALL CC,NN OK
120 RET OK
121 RET CC OK
122 RETN OK
123 RETI OK
124 RETI/RETN OK
125 PUSH+POP RR OK
126 POP+PUSH AF OK
127 PUSH+POP XY OK
128 EX DE,HL OK
129 EX AF,AF' OK
130 EXX OK
131 EX (SP),HL OK
132 EX (SP),XY OK
133 LD [R,(HL)],[R,(HL)] OK
134 LD [X,(XY)],[X,(XY)] OK
135 LD R,(XY) OK
136 LD (XY),R OK
137 LD [R,(HL)],N OK
138 LD X,N OK
139 LD (XY),N OK
140 LD A,([BC,DE]) OK
141 LD ([BC,DE]),A OK
142 LD A,(NN) OK
143 LD (NN),A OK
144 LD RR,NN OK
145 LD XY,NN OK
146 LD HL,(NN) OK
147 LD XY,(NN) OK
148 LD RR,(NN) OK
149 LD (NN),HL OK
150 LD (NN),XY OK
151 LD (NN),RR OK
152 LD SP,HL OK
153 LD SP,XY OK
154 LD I,A OK
155 LD R,A OK
156 LD A,I OK
157 LD A,R OK
158 EI+DI OK
159 IM N OK

Result: all tests passed.

info: Test flags.tap took 556734400 cycles, and ran in 0.41s
info: Test flags.tap ran at 1368.82 MHz (200.00 MIPS)
```
</details>

<!-- z80memptr output -->
<details>
<summary>z80memptr output</summary>

```
Z80 z80test Tests

info: Running z80memptr.tap

Z80 MEMPTR test  2012 RAXOFT

000 SELF TEST OK
001 SCF OK
002 CCF OK
003 SCF (NEC) Skipped
004 CCF (NEC) Skipped
005 SCF (ST) Skipped
006 CCF (ST) Skipped
007 SCF+CCF OK
008 CCF+SCF OK
009 DAA OK
010 CPL OK
011 NEG OK
012 NEG' OK
013 ADD A,N OK
014 ADC A,N OK
015 SUB A,N OK
016 SBC A,N OK
017 AND N OK
018 XOR N OK
019 OR N OK
020 CP N OK
021 ALO A,A OK
022 ALO A,[B,C] OK
023 ALO A,[D,E] OK
024 ALO A,[H,L] OK
025 ALO A,(HL) OK
026 ALO A,[HX,LX] OK
027 ALO A,[HY,LY] OK
028 ALO A,(XY) OK
029 RLCA OK
030 RRCA OK
031 RLA OK
032 RRA OK
033 RLD OK
034 RRD OK
035 RLC A OK
036 RRC A OK
037 RL A OK
038 RR A OK
039 SLA A OK
040 SRA A OK
041 SLIA A OK
042 SRL A OK
043 RLC [R,(HL)] OK
044 RRC [R,(HL)] OK
045 RL [R,(HL)] OK
046 RR [R,(HL)] OK
047 SLA [R,(HL)] OK
048 SRA [R,(HL)] OK
049 SLIA [R,(HL)] OK
050 SRL [R,(HL)] OK
051 SRO (XY) OK
052 SRO (XY),R OK
053 INC A OK
054 DEC A OK
055 INC [R,(HL)] OK
056 DEC [R,(HL)] OK
057 INC X OK
058 DEC X OK
059 INC (XY) OK
060 DEC (XY) OK
061 INC RR OK
062 DEC RR OK
063 INC XY OK
064 DEC XY OK
065 ADD HL,RR OK
066 ADD IX,RR OK
067 ADD IY,RR OK
068 ADC HL,RR OK
069 SBC HL,RR OK
070 BIT N,A OK
071 BIT N,(HL) OK
072 BIT N,[R,(HL)] OK
073 BIT N,(XY) OK
074 BIT N,(XY),- OK
075 SET N,A OK
076 SET N,(HL) OK
077 SET N,[R,(HL)] OK
078 SET N,(XY) OK
079 SET N,(XY),R OK
080 RES N,A OK
081 RES N,(HL) OK
082 RES N,[R,(HL)] OK
083 RES N,(XY) OK
084 RES N,(XY),R OK
085 LDI OK
086 LDD OK
087 LDIR OK
088 LDDR OK
089 LDIR->NOP' OK
090 LDDR->NOP' OK
091 CPI OK
092 CPD OK
093 CPIR OK
094 CPDR OK
095 IN A,(N) OK
096 IN R,(C) OK
097 IN (C) OK
098 INI OK
099 IND OK
100 INIR OK
101 INDR OK
102 INIR->NOP' OK
103 INDR->NOP' OK
104 OUT (N),A OK
105 OUT (C),R OK
106 OUT (C),0 OK
107 OUTI OK
108 OUTD OK
109 OTIR OK
110 OTDR OK
111 JP NN OK
112 JP CC,NN OK
113 JP (HL) OK
114 JP (XY) OK
115 JR N OK
116 JR CC,N OK
117 DJNZ N OK
118 CALL NN OK
119 CALL CC,NN OK
120 RET OK
121 RET CC OK
122 RETN OK
123 RETI OK
124 RETI/RETN OK
125 PUSH+POP RR OK
126 POP+PUSH AF OK
127 PUSH+POP XY OK
128 EX DE,HL OK
129 EX AF,AF' OK
130 EXX OK
131 EX (SP),HL OK
132 EX (SP),XY OK
133 LD [R,(HL)],[R,(HL)] OK
134 LD [X,(XY)],[X,(XY)] OK
135 LD R,(XY) OK
136 LD (XY),R OK
137 LD [R,(HL)],N OK
138 LD X,N OK
139 LD (XY),N OK
140 LD A,([BC,DE]) OK
141 LD ([BC,DE]),A OK
142 LD A,(NN) OK
143 LD (NN),A OK
144 LD RR,NN OK
145 LD XY,NN OK
146 LD HL,(NN) OK
147 LD XY,(NN) OK
148 LD RR,(NN) OK
149 LD (NN),HL OK
150 LD (NN),XY OK
151 LD (NN),RR OK
152 LD SP,HL OK
153 LD SP,XY OK
154 LD I,A OK
155 LD R,A OK
156 LD A,I OK
157 LD A,R OK
158 EI+DI OK
159 IM N OK

Result: all tests passed.

info: Test memptr.tap took 564118113 cycles, and ran in 0.40s
info: Test memptr.tap ran at 1394.64 MHz (202.76 MIPS)
```
</details>

<!-- z80ccf output -->
<details>
<summary>z80ccf output</summary>

```
Z80 z80test Tests

info: Running z80ccf.tap

Z80 CCF test  2012 RAXOFT

000 SELF TEST OK
001 SCF OK
002 CCF OK
003 SCF (NEC) Skipped
004 CCF (NEC) Skipped
005 SCF (ST) Skipped
006 CCF (ST) Skipped
007 SCF+CCF OK
008 CCF+SCF OK
009 DAA OK
010 CPL OK
011 NEG OK
012 NEG' OK
013 ADD A,N OK
014 ADC A,N OK
015 SUB A,N OK
016 SBC A,N OK
017 AND N OK
018 XOR N OK
019 OR N OK
020 CP N OK
021 ALO A,A OK
022 ALO A,[B,C] OK
023 ALO A,[D,E] OK
024 ALO A,[H,L] OK
025 ALO A,(HL) OK
026 ALO A,[HX,LX] OK
027 ALO A,[HY,LY] OK
028 ALO A,(XY) OK
029 RLCA OK
030 RRCA OK
031 RLA OK
032 RRA OK
033 RLD OK
034 RRD OK
035 RLC A OK
036 RRC A OK
037 RL A OK
038 RR A OK
039 SLA A OK
040 SRA A OK
041 SLIA A OK
042 SRL A OK
043 RLC [R,(HL)] OK
044 RRC [R,(HL)] OK
045 RL [R,(HL)] OK
046 RR [R,(HL)] OK
047 SLA [R,(HL)] OK
048 SRA [R,(HL)] OK
049 SLIA [R,(HL)] OK
050 SRL [R,(HL)] OK
051 SRO (XY) OK
052 SRO (XY),R OK
053 INC A OK
054 DEC A OK
055 INC [R,(HL)] OK
056 DEC [R,(HL)] OK
057 INC X OK
058 DEC X OK
059 INC (XY) OK
060 DEC (XY) OK
061 INC RR OK
062 DEC RR OK
063 INC XY OK
064 DEC XY OK
065 ADD HL,RR OK
066 ADD IX,RR OK
067 ADD IY,RR OK
068 ADC HL,RR OK
069 SBC HL,RR OK
070 BIT N,A OK
071 BIT N,(HL) OK
072 BIT N,[R,(HL)] OK
073 BIT N,(XY) OK
074 BIT N,(XY),- OK
075 SET N,A OK
076 SET N,(HL) OK
077 SET N,[R,(HL)] OK
078 SET N,(XY) OK
079 SET N,(XY),R OK
080 RES N,A OK
081 RES N,(HL) OK
082 RES N,[R,(HL)] OK
083 RES N,(XY) OK
084 RES N,(XY),R OK
085 LDI OK
086 LDD OK
087 LDIR OK
088 LDDR OK
089 LDIR->NOP' OK
090 LDDR->NOP' OK
091 CPI OK
092 CPD OK
093 CPIR OK
094 CPDR OK
095 IN A,(N) OK
096 IN R,(C) OK
097 IN (C) OK
098 INI OK
099 IND OK
100 INIR OK
101 INDR OK
102 INIR->NOP' OK
103 INDR->NOP' OK
104 OUT (N),A OK
105 OUT (C),R OK
106 OUT (C),0 OK
107 OUTI OK
108 OUTD OK
109 OTIR OK
110 OTDR OK
111 JP NN OK
112 JP CC,NN OK
113 JP (HL) OK
114 JP (XY) OK
115 JR N OK
116 JR CC,N OK
117 DJNZ N OK
118 CALL NN OK
119 CALL CC,NN OK
120 RET OK
121 RET CC OK
122 RETN OK
123 RETI OK
124 RETI/RETN OK
125 PUSH+POP RR OK
126 POP+PUSH AF OK
127 PUSH+POP XY OK
128 EX DE,HL OK
129 EX AF,AF' OK
130 EXX OK
131 EX (SP),HL OK
132 EX (SP),XY OK
133 LD [R,(HL)],[R,(HL)] OK
134 LD [X,(XY)],[X,(XY)] OK
135 LD R,(XY) OK
136 LD (XY),R OK
137 LD [R,(HL)],N OK
138 LD X,N OK
139 LD (XY),N OK
140 LD A,([BC,DE]) OK
141 LD ([BC,DE]),A OK
142 LD A,(NN) OK
143 LD (NN),A OK
144 LD RR,NN OK
145 LD XY,NN OK
146 LD HL,(NN) OK
147 LD XY,(NN) OK
148 LD RR,(NN) OK
149 LD (NN),HL OK
150 LD (NN),XY OK
151 LD (NN),RR OK
152 LD SP,HL OK
153 LD SP,XY OK
154 LD I,A OK
155 LD R,A OK
156 LD A,I OK
157 LD A,R OK
158 EI+DI OK
159 IM N OK

Result: all tests passed.

info: Test ccf.tap took 603147822 cycles, and ran in 0.42s
info: Test ccf.tap ran at 1422.14 MHz (208.41 MIPS)
```
</details>

## Resources

#### Documentation

- [Z80 CPU User Manual][Z80 CPU User Manual]
- [The Undocumented Z80 Documented][The Undocumented Z80 Documented]
- [Z80 Opcode table][Z80 Opcode table]
- [Z80 Undocumented Instructions][Z80 Undocumented Instructions]
- [Decoding Z80 Opcodes][Decoding Z80 Opcodes]
- [Interrupt Behaviour of the Z80 CPU][Interrupt Behaviour of the Z80 CPU]

#### Tests

- [Single Step Tests][Single Step Tests]
- [Z80 Instruction Set Exerciser][Z80 Instruction Set Exerciser]
- [Zilog Z80 CPU Test Suite][Zilog Z80 CPU Test Suite]

#### References

- [superzazu/z80][superzazu/z80]
- [Pdawg-bytes/Z80Sharp][Pdawg-bytes/Z80Sharp]
- [redcode/Z80][redcode/Z80]

#### Getting help

- [Emulator Development Discord server][Emulator Development Discord server]

## License

This project is licensed under the **MIT License** - see the [LICENSE](./LICENSE) file for details.

<!-- Links -->

[z80]: https://en.wikipedia.org/wiki/Zilog_Z80
[Zig]: https://ziglang.org/
<!-- Documentation -->
[Z80 CPU User Manual]: https://www.zilog.com/force_download.php?filepath=YUhSMGNEb3ZMM2QzZHk1NmFXeHZaeTVqYjIwdlpHOWpjeTk2T0RBdlZVMHdNRGd3TG5Ca1pnPT0=
[The Undocumented Z80 Documented]: http://www.z80.info/zip/z80-documented.pdf
[Z80 Opcode table]: https://clrhome.org/table/
[Z80 Undocumented Instructions]: http://www.z80.info/z80undoc.htm
[Decoding Z80 Opcodes]: http://z80.info/decoding.htm
[Interrupt Behaviour of the Z80 CPU]: http://z80.info/interrup.htm
<!-- Tests -->
[Single Step Tests]: https://github.com/SingleStepTests/z80
[Z80 Instruction Set Exerciser]: https://zxe.io/depot/software/POSIX/Yaze%20v1.14%20%282004-04-23%29%28Cringle,%20Frank%20D.%29%28Sources%29%5B%21%5D.tar.gz
[Zilog Z80 CPU Test Suite]: https://github.com/raxoft/z80test
<!-- References -->
[superzazu/z80]: https://github.com/superzazu/z80
[Pdawg-bytes/Z80Sharp]: https://github.com/Pdawg-bytes/Z80Sharp
[redcode/Z80]: https://github.com/redcode/Z80
<!-- Getting help -->
[Emulator Development Discord server]: https://discord.com/invite/7nuaqZ2

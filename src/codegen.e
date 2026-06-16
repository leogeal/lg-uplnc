/*                    -*- C -*-                                            */
/*               code generation by E.V., (C) 2003                         */
/*
  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.
  
  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.
  
  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*/
#include "codegen.he"
var extern *int:stderr;
var extern int:stlab;

func cg_init(this:*scodegen)
{
  this->ncodeitems=NCODEITEMS;
  chkmem(this->codes=calloc(this->ncodeitems,sizeof(scode)));
  this->codeptr=0;
}
func cg_done(this:*scodegen)
{
  if(this->codes)
  {
    var i:int;
    for(i=0;i<this->codeptr;i++)
    cd_done(this->codes+i);
    free(this->codes);
  }
  this->codes=0;
  this->codeptr=0;
  this->ncodeitems=0;
}
func cg_getitem(this :*scodegen)
{
  if(this->codeptr>=this->ncodeitems)
  {
    this->ncodeitems=this->ncodeitems+NCODEITEMS;
    /*fprintf(stderr,"ncodeitems=%d, reallocating\n",
    this->ncodeitems);*/
    chkmem(this->codes=realloc(this->codes,
                 this->ncodeitems*sizeof(scode)));
  }
  cd_init(this->codes+this->codeptr);
  return this->codes+this->codeptr++;
}
/* emit "<mnem> <a>, <b>" -- the backends call this for CD_MOVR with their own
   operand order (AT&T x86 is src,dst; arm64/riscv/mips are dst,src). */
func movins(mnem:*char,a:*char,b:*char)
{
  ot(mnem);outstr(a);outstr(", ");outstr(b);nl();
}
/* emit "<mnem> <d>, <a>, <b>" -- the 3-operand RISC arithmetic form. */
func op3(mnem:*char,d:*char,a:*char,b:*char)
{
  ot(mnem);outstr(d);outstr(", ");outstr(a);outstr(", ");outstr(b);nl();
}
/* The 2nd-operand register for a binary op. Default RG_D (the popped operand);
   when regspill kept the operand in a save register it sets scode.reg to it, so
   the op reads it straight from there and the spill->RG_D move is dropped. */
func r2nd(this:*scode)
{
  if(this->reg)return regnames[this->reg];
  return regnames[RG_D];
}
/* binary ops that consume the 2nd operand (the popped/saved left operand) */
func is2ndop(code:int)
{
  return ((code>=CD_ADD2REGS)&&(code<=CD_UGT))
       ||(code==CD_MUL2REGS)||(code==CD_DIV2REGS)||(code==CD_MOD2REGS);
}
func ispureload(code:int)
{
  /* M5: opcodes that load a value into the accumulator (%rax) and read neither
     %rax nor %rdx -- so the value can be commuted past a saved left operand.
     Deliberately excludes CD_LBR* (those dereference %rax). */
  return (code==CD_LDLIT)||(code==CD_LDN)||(code==CD_LDA)||(code==CD_LEA)
       ||(code==CD_LDW)||(code==CD_LDB)||(code==CD_LDLW)||(code==CD_LDLB);
}
/* M5 peephole optimizer: target-neutral rewrites over the CD_* stream, run just
   before lowering, so both backends (and both self-host fixpoints) benefit.
   Eliminated items become CD_IGNORE (lowered to nothing), so indices are
   stable and a single forward pass suffices. */
func peephole(this:*scodegen)
{
  var int:i;var int:n;var int:j;
  n=this->codeptr;
  i=0;
  while(i<n)
  {
    /* A/D: a binary op whose right operand is a single accumulator-only load
       doesn't need the stack. If the left operand (the instruction just before
       the PUSH) is *also* a pure load, retarget it straight into the 2nd
       register (reg=RG_D) and drop the PUSH/POP outright; otherwise keep the
       left operand in the 2nd register with a MOVAD copy.
         <load X> ; PUSH ; <load Y> ; POP  ==>  <load X -> 2nd> ; <load Y>
                   PUSH ; <load Y> ; POP   ==>  MOVAD ; <load Y>            */
    if((i+2<n)&&(this->codes[i].code==CD_PUSH)
       &&ispureload(this->codes[i+1].code)
       &&(this->codes[i+2].code==CD_POP))
    {
      if((i>0)&&ispureload(this->codes[i-1].code))
      {
        this->codes[i-1].reg=RG_D;          /* left operand -> 2nd register */
        this->codes[i].code=CD_IGNORE;      /* drop PUSH */
        this->codes[i+2].code=CD_IGNORE;    /* drop POP */
      }
      else
      {
        this->codes[i].code=CD_MOVAD;
        this->codes[i+2].code=CD_IGNORE;
      }
      i=i+3;
    }
    /* B: code after an unconditional RET/JUMP is unreachable until the next
       label -- drop it (e.g. the function epilogue after a trailing return). */
    else if((this->codes[i].code==CD_RET)||(this->codes[i].code==CD_JUMP))
    {
      j=i+1;
      while((j<n)&&(this->codes[j].code!=CD_LAB))
      {this->codes[j].code=CD_IGNORE;j=j+1;}
      i=j;
    }
    else i=i+1;
  }
}
/* M5 light register allocation (slice 1), as a target-neutral peephole over the
   CD_* stream, run after peephole() so the easy pure-load pairs are already
   gone. A binary op saves its left operand across the (complex) right operand;
   instead of spilling it to the *memory* operand stack (PUSH/POP) we hold it in
   a free register (RG_B, then RG_C) and copy it to RG_D for the operate step:
     PUSH ; <right> ; POP            (memory round-trip)
     mov acc->RG_B ; <right> ; mov RG_B->RG_D     (register, no memory)
   RG_B/RG_C are otherwise unused as IR destinations on every backend, so the
   only thing that can clobber a held save in a call-free span is a *nested*
   save -- which takes the next register (the openreg discipline). A function
   CALL, though, clobbers them (they are caller-saved on arm64/riscv/mips), so a
   span containing a CD_ZCALL reverts to the memory PUSH/POP. PUSH/POP are
   balanced per function, so a simple match-stack pairs them; nesting deeper than
   two register saves (or REGSPILL_MAX) just stays in memory. */
#define REGSPILL_MAX 256
func regspill(this:*scodegen)
{
  var int:i;var int:n;var int:j;var int:r;var int:c;var int:done;
  var int:sp;var int:openreg;var int:bail;
  var [REGSPILL_MAX]int:sidx;   /* PUSH index of each open save            */
  var [REGSPILL_MAX]int:sreg;   /* its register (RG_B/RG_C), or 0-1 = memory */
  n=this->codeptr;
  sp=0;openreg=0;bail=0;
  i=0;
  while(i<n)
  {
    c=this->codes[i].code;
    if(c==CD_ZCALL)              /* clobbers every register-held open save */
    {
      for(j=0;j<sp;j++)if(sreg[j]>=0)sreg[j]=0-1;
      openreg=0;
    }
    else if(c==CD_PUSH)
    {
      if(bail||(sp>=REGSPILL_MAX))bail=1;  /* too deep -> leave the rest in memory */
      else
      {
        sidx[sp]=i;
        if(openreg<target.nsavereg){sreg[sp]=RG_B+openreg;openreg=openreg+1;}
        else sreg[sp]=0-1;       /* no free save reg -> memory */
        sp=sp+1;
      }
    }
    else if(c==CD_POP)
    {
      if((!bail)&&(sp>0))
      {
        sp=sp-1;
        r=sreg[sp];
        if(r>=0)
        {
          openreg=openreg-1;
          /* PUSH -> save the accumulator into the register r */
          this->codes[sidx[sp]].code=CD_MOVR;
          this->codes[sidx[sp]].reg=r;
          this->codes[sidx[sp]].arg=RG_A;
          /* POP: if the backend's op lowerings read their 2nd operand via r2nd
             (directop) and the next live opcode is such a binary op, point it at
             r and drop the POP outright; otherwise copy r into RG_D as before. */
          done=0;
          if(target.directop)
          {
            j=i+1;
            while((j<n)&&(this->codes[j].code==CD_IGNORE))j=j+1;
            if((j<n)&&is2ndop(this->codes[j].code))
            {this->codes[j].reg=r;this->codes[i].code=CD_IGNORE;done=1;}
          }
          if(!done)
          {this->codes[i].code=CD_MOVR;this->codes[i].reg=RG_D;this->codes[i].arg=r;}
        }
      }
    }
    i=i+1;
  }
}
func cg_print(*scodegen this)
{
  var int:i;
  peephole(this);
  regspill(this);
  for(i=0;i<this->codeptr;i++)
  cd_write(this->codes+i);
}
func cg_transfer(*scodegen this,*scodegen dest)
{
  /*fprintf(stderr,"transfer(),dest=%d\n",dest);*/
  var int:i;
  for(i=0;i<this->codeptr;++i)
  cg_insert(dest,this->codes+i);
  /*fprintf(stderr,"!transfer()\n");*/
}
func cg_insert(*scodegen this,*scode s)
{
  /*fprintf(stderr,"insert()\n");*/
  var *scode:d;
  d=cg_getitem(this);
  d->code=s->code;
  d->arg=s->arg;
  d->reg=s->reg;
  if(s->str)
  d->str=strdyn(s->str);
  else
  d->str=0;
  /*fprintf(stderr,"!insert()\n");*/
}
/* cd_write lowers one IR opcode to assembly. It dispatches to the per-target
   backend selected by target.arch (M2 Phase 2a). UPLNC has no function
   pointers, so this is an arch-id switch rather than a vtable. */
func cd_write(*scode:this)
{
  if(target.arch==ARCH_X86_64)cd_write_x86_64(this);
  else if(target.arch==ARCH_ARM64)cd_write_arm64(this);
  else if(target.arch==ARCH_RISCV)cd_write_riscv(this);
  else if(target.arch==ARCH_MIPS)cd_write_mips(this);
  else cd_write_i386(this);
}
/* System V AMD64 integer/pointer argument registers, in order. */
func sysvargreg(i:int)
{
  if(i==0)return "%rdi";
  else if(i==1)return "%rsi";
  else if(i==2)return "%rdx";
  else if(i==3)return "%rcx";
  else if(i==4)return "%r8";
  else if(i==5)return "%r9";
  error("x86_64: more than 6 register arguments not supported");
  return "%rax";
}
func xmmreg(i:int)   /* M4: System V floating-point argument registers */
{
  if(i==0)return "%xmm0";
  else if(i==1)return "%xmm1";
  else if(i==2)return "%xmm2";
  else if(i==3)return "%xmm3";
  else if(i==4)return "%xmm4";
  else if(i==5)return "%xmm5";
  else if(i==6)return "%xmm6";
  else if(i==7)return "%xmm7";
  error("x86_64: more than 8 floating-point arguments not supported");
  return "%xmm0";
}
/* x86_64 (System V) instruction lowering. Mirrors cd_write_i386 with 64-bit
   registers and `q` suffixes; UPLNC's word is 8 bytes here (int==pointer).
   Calls follow the SysV ABI (register args, 16-byte alignment) -- see
   CD_ZCALL / CD_MARSHAL / CD_SPILLARGS and the caller code in langc.e. */
func cd_write_x86_64(*scode:this)
{
  if(this->code==CD_ZCALL)
  {
    /* System V AMD64: args are already in %rdi../%xmm.. (via CD_MARSHAL etc.)
       and %rsp is 16-byte aligned. %al = number of vector (xmm) registers used,
       required for variadic callees like printf (this->arg). */
    ot("movb $");
    outdec(this->arg);
    outstr(", %al");
    nl();
    ot("call ");
    outname(this->str);
    nl();
    /* getchar/fgetc return a 32-bit int in %eax with the upper half of %rax
       undefined, and the compiler compares that result (EOF / char value), so
       sign-extend %eax->%rax. Do NOT extend other calls: pointer/long returns
       (strcat/strcpy return a possibly-high stack address, calloc/fopen a heap
       pointer, UPLNC functions set the full %rax) would be corrupted. */
    if(this->str)
    if(strid(this->str,"getchar")||strid(this->str,"fgetc")||strid(this->str,"getc"))
    ol("cltq");
  }
  else if(this->code==CD_SPILLARGS)
  {
    /* callee prologue: spill the incoming arg registers to their param slots
       (-8(%rbp), -16(%rbp), ...), so params resolve as ordinary stack slots. */
    var int:i;
    for(i=0;i<this->arg;i++)
    {
      ot("movq ");
      outstr(sysvargreg(i));
      outstr(", ");
      outdec(-(i+1)*target.wordsize);
      outstr("(%rbp)");
      nl();
    }
  }
  else if(this->code==CD_MARSHAL)
  {
    /* caller: load the pushed args (arg1 at (%rsp), arg2 at wordsize(%rsp), ...)
       into the SysV argument registers. */
    var int:i;
    for(i=0;i<this->arg;i++)
    {
      ot("movq ");
      outdec(i*target.wordsize);
      outstr("(%rsp), ");
      outstr(sysvargreg(i));
      nl();
    }
  }
  else if(this->code==CD_LAB)
  {
    printlab(this->arg);
    col();
    nl();
  }
  else if(this->code==CD_JUMP)
  {
    ot("jmp ");
    printlab(this->arg);
    nl();
  }
  else if(this->code==CD_TESTJUMP)
  {
    ol("testq %rax, %rax");
    ot("je");
    tab();
    printlab(this->arg);
    nl();
  }
  else if(this->code==CD_TESTNEJUMP)
  {
    ol("testq %rax, %rax");
    ot("jne");
    tab();
    printlab(this->arg);
    nl();
  }
  else if(this->code==CD_NEG)
  {
    ol("negq %rax");
  }
  else if(this->code==CD_LNOT)
  {
    ol("testq %rax,%rax");
    ol("sete %al");
    ol("movzbq %al, %rax");
  }
  else if(this->code==CD_BNOT)
  {
    ol("notq %rax");
  }
  else if(this->code==CD_EQ)
  {
    ol("cmpq %rax, %rdx");
    ol("sete %al");
    ol("movzbq %al, %rax");
  }
  else if(this->code==CD_NEQ)
  {
    ol("cmpq %rax, %rdx");
    ol("setne %al");
    ol("movzbq %al, %rax");
  }
  else if(this->code==CD_ZGE)
  {
    ol("cmpq %rax, %rdx");
    ol("setge %al");
    ol("movzbq %al, %rax");
  }
  else if(this->code==CD_UGE)
  {
    ol("cmpq %rax, %rdx");
    ol("setae %al");
    ol("movzbq %al, %rax");
  }
  else if(this->code==CD_ZLE)
  {
    ol("cmpq %rax, %rdx");
    ol("setle %al");
    ol("movzbq %al, %rax");
  }
  else if(this->code==CD_ULE)
  {
    ol("cmpq %rax, %rdx");
    ol("setbe %al");
    ol("movzbq %al, %rax");
  }
  else if(this->code==CD_ZLT)
  {
    ol("cmpq %rax, %rdx");
    ol("setl %al");
    ol("movzbq %al, %rax");
  }
  else if(this->code==CD_ULT)
  {
    ol("cmpq %rax, %rdx");
    ol("setb %al");
    ol("movzbq %al, %rax");
  }
  else if(this->code==CD_ZGT)
  {
    ol("cmpq %rax, %rdx");
    ol("setg %al");
    ol("movzbq %al, %rax");
  }
  else if(this->code==CD_UGT)
  {
    ol("cmpq %rax, %rdx");
    ol("seta %al");
    ol("movzbq %al, %rax");
  }
  else if(this->code==CD_BOR2REGS)
  {
    ol("orq %rdx, %rax");
  }
  else if(this->code==CD_BXOR2REGS)
  {
    ol("xorq %rdx, %rax");
  }
  else if(this->code==CD_BAND2REGS)
  {
    ol("andq %rdx, %rax");
  }
  else if(this->code==CD_ADD2REGS)
  {
    ol("addq %rdx, %rax");
  }
  else if(this->code==CD_SUB2REGS)
  {
    ol("subq %rax, %rdx");
    ol("movq %rdx, %rax");
  }
  else if(this->code==CD_MUL2REGS)
  {
    ol("imulq %rdx");
  }
  else if(this->code==CD_DIV2REGS)
  {
    ol("xchgq %rax, %rdx");
    ol("movq %rdx, %rcx");
    ol("cqto");
    ol("idivq %rcx");
  }
  else if(this->code==CD_MOD2REGS)
  {
    ol("xchgq %rax, %rdx");
    ol("movq %rdx, %rcx");
    ol("cqto");
    ol("idivq %rcx");
    ol("movq %rdx, %rax");
  }
  else if(this->code==CD_STKENTER)
  {
    ol("pushq %rbp");
    ol("movq %rsp, %rbp");
  }
  else if(this->code==CD_STKLEAVE)
  {
    ol("movq %rbp, %rsp");
    ol("popq %rbp");
  }
  else if(this->code==CD_INCREG)
  {
    if(this->arg>0)
    {
      if(this->arg<3)
      while(this->arg--)
        ol("incq %rax");
      else
      {
        ot("addq $");
        outdec(this->arg);
        outstr(", %rax");
        nl();
      }
    }
  }
  else if(this->code==CD_DECREG)
  {
    if(this->arg>0)
    {
      if(this->arg<3)
      while(this->arg--)
        ol("decq %rax");
      else
      {
        ot("subq $");
        outdec(this->arg);
        outstr(", %rax");
        nl();
      }
    }
  }
  else if(this->code==CD_MODSTK)
  {
    if(this->arg>0)
    {
      ot("addq $");
      outdec(this->arg);
      outasm(", %rsp");
      nl();
    }
    else if(this->arg<0)
    {
      ot("subq $");
      outdec(-this->arg);
      outasm(", %rsp");
      nl();
    }
  }
  else if(this->code==CD_SHL)
  {
    ol("movq %rax, %rcx");
    ol("movq %rdx, %rax");
    ol("salq %cl, %rax");
  }
  else if(this->code==CD_ASR)
  {
    ol("movq %rax, %rcx");
    ol("movq %rdx, %rax");
    ol("sarq %cl, %rax");
  }
  else if(this->code==CD_SHR)
  {
    ol("movq %rax, %rcx");
    ol("movq %rdx, %rax");
    ol("shrq %cl, %rax");
  }
  else if(this->code==CD_MULREG)
  {
    xmulreg_x86_64(this->arg,this->reg[regnames]);
  }
  else if(this->code==CD_DIVCONST)
  {
    xdivconst_x86_64(this->arg);
  }
  else if(this->code==CD_PUSH)
  {
    ol("pushq %rax");
  }
  else if(this->code==CD_POP)
  {
    ol("popq %rdx");
  }
  else if(this->code==CD_MOVAD)
  ol("movq %rax, %rdx");
  else if(this->code==CD_MOVR)   /* AT&T: src, dst */
  movins("movq ",regnames[this->arg],regnames[this->reg]);
  else if(this->code==CD_RET)
  {
    ol("ret");
  }
  else if(this->code==CD_LDLIT)
  {
    ot("movq $");
    printlab(stlab);
    outstr("+");
    outdec(this->arg);
    outstr(", ");outstr(regnames[this->reg]);
    nl();
  }
  else if(this->code==CD_LDN)
  {
    if(this->arg==0)
    {ot("xorq ");outstr(regnames[this->reg]);outstr(", ");outstr(regnames[this->reg]);nl();}
    else
    {
      ot("movq $");
      outdec(this->arg);
      outstr(", ");outstr(regnames[this->reg]);
      nl();
    }
  }
  else if(this->code==CD_LDA)
  {
    ot("movq $");
    outname(this->str);
    if(this->arg)
    {outasm("+");outdec(this->arg);}
    outasm(", ");outstr(regnames[this->reg]);
    nl();
  }
  else if(this->code==CD_LEA)
  {
    ot("leaq ");
    outdec(this->arg);
    outasm("(%rbp), ");outstr(regnames[this->reg]);
    nl();
  }
  else if(this->code==CD_STOW)
  {
    ot("movq %rax, ");
    outname(this->str);
    if(this->arg)
    {outstr("+");outdec(this->arg);}
    nl();
  }
  else if(this->code==CD_STOB)
  {
    ot("movb %al, ");
    outname(this->str);
    if(this->arg)
    {outstr("+");outdec(this->arg);}
    nl();
  }
  else if(this->code==CD_STOB2)
  {
    ot("movb %al, ");
    outdec(this->arg);
    outstr("(%rdx)");nl();
  }
  else if(this->code==CD_STOW2)
  {
    ot("movq %rax, ");
    outdec(this->arg);
    outstr("(%rdx)");nl();
  }
  else if(this->code==CD_STLW)
  {
    ot("movq %rax, ");
    outdec(this->arg);outasm("(%rbp)");nl();
  }
  else if(this->code==CD_STLB)
  {
    ot("movb %al, ");
    outdec(this->arg);outasm("(%rbp)");nl();
  }
  else if(this->code==CD_LBRB)
  {
    ot("movsbq ");
    outdec(this->arg);
    outstr("(%rax), %rax");nl();
  }
  else if(this->code==CD_LBRW)
  {
    ot("movq ");
    outdec(this->arg);
    outstr("(%rax), %rax");nl();
  }
  else if(this->code==CD_LBRA)
  {
    ot("leaq ");
    outdec(this->arg);
    outstr("(%rax), %rax");nl();
  }
  else if(this->code==CD_LDW)
  {
    ot("movq ");
    outname(this->str);
    if(this->arg)
    {
      outasm("+");
      outdec(this->arg);
    }
    outasm(", ");outstr(regnames[this->reg]);nl();
  }
  else if(this->code==CD_LDB)
  {
    ot("movsbq ");
    outname(this->str);
    if(this->arg)
    {
      outasm("+");
      outdec(this->arg);
    }
    outasm(", ");outstr(regnames[this->reg]);nl();
  }
  else if(this->code==CD_LDLW)
  {
    ot("movq ");
    outdec(this->arg);
    outasm("(%rbp), ");outstr(regnames[this->reg]);
    nl();
  }
  else if(this->code==CD_LDLB)
  {
    ot("movsbq ");
    outdec(this->arg);
    outasm("(%rbp), ");outstr(regnames[this->reg]);
    nl();
  }
  else if(this->code==CD_FLDLIT)
  {
    /* load a double literal from .rodata into the FP accumulator %xmm0 */
    ot("movsd ");
    outstr(".LF");
    outdec(this->arg);
    outstr("(%rip), %xmm0");
    nl();
  }
  else if(this->code==CD_F2I)
  {
    ol("cvttsd2si %xmm0, %rax");
  }
  else if(this->code==CD_FLDLOC)
  {
    ot("movsd ");outdec(this->arg);outstr("(%rbp), %xmm0");nl();
  }
  else if(this->code==CD_FLDGLB)
  {
    ot("movsd ");outname(this->str);
    if(this->arg){outasm("+");outdec(this->arg);}
    outstr(", %xmm0");nl();
  }
  else if(this->code==CD_FSTLOC)
  {
    ot("movsd %xmm0, ");outdec(this->arg);outstr("(%rbp)");nl();
  }
  else if(this->code==CD_FSTGLB)
  {
    ot("movsd %xmm0, ");outname(this->str);
    if(this->arg){outasm("+");outdec(this->arg);}
    nl();
  }
  else if(this->code==CD_FLDLOCS)
  {
    /* load a 4-byte float and widen it into the (double) FP accumulator */
    ot("cvtss2sd ");outdec(this->arg);outstr("(%rbp), %xmm0");nl();
  }
  else if(this->code==CD_FLDGLBS)
  {
    ot("cvtss2sd ");outname(this->str);
    if(this->arg){outasm("+");outdec(this->arg);}
    outstr(", %xmm0");nl();
  }
  else if(this->code==CD_FSTLOCS)
  {
    /* narrow the double accumulator to single in %xmm1 (preserving %xmm0) and
       store its 4 bytes */
    ol("cvtsd2ss %xmm0, %xmm1");
    ot("movss %xmm1, ");outdec(this->arg);outstr("(%rbp)");nl();
  }
  else if(this->code==CD_FSTGLBS)
  {
    ol("cvtsd2ss %xmm0, %xmm1");
    ot("movss %xmm1, ");outname(this->str);
    if(this->arg){outasm("+");outdec(this->arg);}
    nl();
  }
  else if(this->code==CD_FLBR)
  {
    /* load a double from the address in %rax (deref / array element) */
    ot("movsd ");outdec(this->arg);outstr("(%rax), %xmm0");nl();
  }
  else if(this->code==CD_FLBRS)
  {
    /* load a 4-byte float from %rax and widen it to a double */
    ot("cvtss2sd ");outdec(this->arg);outstr("(%rax), %xmm0");nl();
  }
  else if(this->code==CD_FSTBR2)
  {
    /* store the double accumulator to the popped address in %rdx */
    ot("movsd %xmm0, ");outdec(this->arg);outstr("(%rdx)");nl();
  }
  else if(this->code==CD_FSTBR2S)
  {
    ol("cvtsd2ss %xmm0, %xmm1");
    ot("movss %xmm1, ");outdec(this->arg);outstr("(%rdx)");nl();
  }
  else if(this->code==CD_FPUSH)
  {
    ol("subq $8, %rsp");
    ol("movsd %xmm0, (%rsp)");
  }
  else if(this->code==CD_FPOP)
  {
    ol("movsd (%rsp), %xmm1");
    ol("addq $8, %rsp");
  }
  else if(this->code==CD_FADD)
  ol("addsd %xmm1, %xmm0");
  else if(this->code==CD_FMUL)
  ol("mulsd %xmm1, %xmm0");
  else if(this->code==CD_FSUB)
  {
    ol("subsd %xmm0, %xmm1");
    ol("movsd %xmm1, %xmm0");
  }
  else if(this->code==CD_FDIV)
  {
    ol("divsd %xmm0, %xmm1");
    ol("movsd %xmm1, %xmm0");
  }
  else if(this->code==CD_I2F)
  ol("cvtsi2sd %rax, %xmm0");
  else if(this->code==CD_I2F1)
  ol("cvtsi2sd %rdx, %xmm1");
  else if(this->code==CD_MARGINT)
  {
    ot("movq ");outdec(this->arg);outstr("(%rsp), ");
    outstr(sysvargreg(this->reg));nl();
  }
  else if(this->code==CD_MARGFP)
  {
    ot("movsd ");outdec(this->arg);outstr("(%rsp), ");
    outstr(xmmreg(this->reg));nl();
  }
  else if(this->code==CD_SARGINT)
  {
    ot("movq ");outstr(sysvargreg(this->reg));outstr(", ");
    outdec(this->arg);outstr("(%rbp)");nl();
  }
  else if(this->code==CD_SARGFP)
  {
    ot("movsd ");outstr(xmmreg(this->reg));outstr(", ");
    outdec(this->arg);outstr("(%rbp)");nl();
  }
  else if(this->code==CD_IGNORE)
  ;
  else
  {
    fprintf(stderr,"%d ",this->code);
    error("unknown opcode (x86_64)");
  }
}
func xdivconst_x86_64(k:int)
{
  var int:l;
  if(k==1)return ;
  if(!k){
  error("division by zero");
  return ;
  }
  l=1;
  while(l<15)if(k==(1<<l)){
  ot("sarq $");
  outdec(l);
  outstr(", %rax");
  nl();
  return ;
  }
  else
  l++;
  ol("cqto");
  ot("divq $");
  outdec(k);
  nl();
}
func xmulreg_x86_64(k:int,s:*char)
{
  var int:l;
  if(k==1)return ;
  else
  if(k==0){
    ot("xorq ");
    outstr(s);
    outstr(", ");
    outstr(s);
    nl();
  }
  else
    {
    l=1;
    while(l<15)if(k==(1<<l)){
      ot("salq $");
      outdec(l);
      outstr(", ");
      outstr(s);
      nl();
      return ;
    }
    else
      l++;
    }
  ot("imulq $");
  outdec(k);
  outstr(", ");
  outstr(s);
  nl();
}
/* ===================== AArch64 (ARM64) backend (M3) =======================
   x0 = accumulator (RG_A), x1 = 2nd operand (RG_D), x9/x10 = scratch, x29 =
   frame pointer, x30 = link register, sp = stack (must stay 16-byte aligned).
   Load/store architecture: arithmetic is register-register; memory needs an
   address. Calls follow AAPCS64 (args x0..x5 here, return x0, `bl`/`ret`).
   Integer/pointer only for now -- the FP opcodes error cleanly. */
func loadimm_arm64(reg:*char,val:int)
{
  /* Load a 32-bit-representable immediate: low 16 bits (movz), bits 16-31
     (movk), then sign-extend a negative value to 64 bits. We deliberately
     avoid >>32/>>48 because the bootstrap stage-0 (uplnc2c -> C) uses 32-bit
     `int`, where those shifts are masked to 0; integer literals in this
     codebase all fit in 32 bits, so this is sufficient and stage-independent. */
  ot("movz ");outstr(reg);outstr(", #");outdec(val&65535);nl();
  if((val>>16)&65535)
  {ot("movk ");outstr(reg);outstr(", #");outdec((val>>16)&65535);outstr(", lsl #16");nl();}
  if(val<0)
  {ot("sxtw ");outstr(reg);outstr(", w");outstr(reg+1);nl();}  /* w<n> of x<n> */
}
func addimm_arm64(dst:*char,src:*char,val:int)
{
  /* dst = src + val (val may be negative); 12-bit immediate, scratch for big */
  var int:a;
  a=val;if(a<0)a=-a;
  if(a<4096)
  {
    if(val<0)ot("sub ");else ot("add ");
    outstr(dst);outstr(", ");outstr(src);outstr(", #");outdec(a);nl();
  }
  else
  {
    loadimm_arm64("x9",a);
    if(val<0)ot("sub ");else ot("add ");
    outstr(dst);outstr(", ");outstr(src);outstr(", x9");nl();
  }
}
func gaddr_arm64(reg:*char,name:*char,off:int)
{
  /* reg = &name[+off], non-PIC (adrp/add :lo12:, fixed at static link) */
  ot("adrp ");outstr(reg);outstr(", ");outname(name);
  if(off){outstr("+");outdec(off);}
  nl();
  ot("add ");outstr(reg);outstr(", ");outstr(reg);outstr(", :lo12:");outname(name);
  if(off){outstr("+");outdec(off);}
  nl();
}
func litaddr_arm64(reg:*char,off:int)
{
  /* reg = &.L<stlab>[+off] (string-literal pool base) */
  ot("adrp ");outstr(reg);outstr(", ");printlab(stlab);
  if(off){outstr("+");outdec(off);}
  nl();
  ot("add ");outstr(reg);outstr(", ");outstr(reg);outstr(", :lo12:");printlab(stlab);
  if(off){outstr("+");outdec(off);}
  nl();
}
func framemem_arm64(op:*char,reg:*char,off:int)
{
  /* op reg, [x29+off]; compute the address in x9 when off is out of range */
  if((off<=255)&&(off>=-256))
  {ot(op);outstr(" ");outstr(reg);outstr(", [x29, #");outdec(off);outstr("]");nl();}
  else
  {addimm_arm64("x9","x29",off);ot(op);outstr(" ");outstr(reg);outstr(", [x9]");nl();}
}
func ptrmem_arm64(op:*char,reg:*char,base:*char,off:int)
{
  /* op reg, [base+off]; fold large off into the base via x9 */
  if((off<=255)&&(off>=-256))
  {ot(op);outstr(" ");outstr(reg);outstr(", [");outstr(base);outstr(", #");outdec(off);outstr("]");nl();}
  else
  {addimm_arm64("x9",base,off);ot(op);outstr(" ");outstr(reg);outstr(", [x9]");nl();}
}
func armcmpset(this:*scode,cond:*char)
{
  ot("cmp ");outstr(r2nd(this));outstr(", x0");nl();   /* left - right (x0=right) */
  ot("cset x0, ");outstr(cond);nl();
}
func spadjust_arm64(a:int,isadd:int)
{
  if(a<4096)
  {
    if(isadd)ot("add sp, sp, #");else ot("sub sp, sp, #");
    outdec(a);nl();
  }
  else
  {
    loadimm_arm64("x9",a);
    if(isadd)ol("add sp, sp, x9");else ol("sub sp, sp, x9");
  }
}
func argreg_arm64(i:int)
{
  if(i==0)return "x0";
  else if(i==1)return "x1";
  else if(i==2)return "x2";
  else if(i==3)return "x3";
  else if(i==4)return "x4";
  else if(i==5)return "x5";
  error("arm64: more than 6 register arguments not supported");
  return "x0";
}
func fpargreg_arm64(i:int)   /* AAPCS64 floating-point arg/return registers */
{
  if(i==0)return "d0";
  else if(i==1)return "d1";
  else if(i==2)return "d2";
  else if(i==3)return "d3";
  else if(i==4)return "d4";
  else if(i==5)return "d5";
  else if(i==6)return "d6";
  else if(i==7)return "d7";
  error("arm64: more than 8 floating-point arguments not supported");
  return "d0";
}
func xmulreg_arm64(k:int,s:*char)
{
  var int:l;
  if(k==1)return ;
  if(k==0){ot("mov ");outstr(s);outstr(", #0");nl();return ;}
  l=1;
  while(l<31)if(k==(1<<l))
  {ot("lsl ");outstr(s);outstr(", ");outstr(s);outstr(", #");outdec(l);nl();return ;}
  else l++;
  loadimm_arm64("x9",k);
  ot("mul ");outstr(s);outstr(", ");outstr(s);outstr(", x9");nl();
}
func xdivconst_arm64(k:int)
{
  var int:l;
  if(k==1)return ;
  if(!k){error("division by zero");return ;}
  l=1;
  while(l<31)if(k==(1<<l))
  {ot("asr x0, x0, #");outdec(l);nl();return ;}
  else l++;
  loadimm_arm64("x9",k);
  ol("sdiv x0, x0, x9");
}
func cd_write_arm64(*scode:this)
{
  if(this->code==CD_ZCALL)
  {
    ot("bl ");outname(this->str);nl();
    /* sign-extend a 32-bit int return (getchar/fgetc) -- the compiler compares
       it; other returns set the full x0 (see the x86_64 cltq note). */
    if(this->str)
    if(strid(this->str,"getchar")||strid(this->str,"fgetc")||strid(this->str,"getc"))
    ol("sxtw x0, w0");
  }
  else if(this->code==CD_SPILLARGS)
  {
    var int:i;
    for(i=0;i<this->arg;i++)
    framemem_arm64("str",argreg_arm64(i),-(i+1)*target.wordsize);
  }
  else if(this->code==CD_MARSHAL)
  {
    /* load the pushed args (16-byte slots) into x0..x5 */
    var int:i;
    for(i=0;i<this->arg;i++)
    {ptrmem_arm64("ldr",argreg_arm64(i),"sp",i*target.stackslot);}
  }
  else if(this->code==CD_LAB)
  {printlab(this->arg);col();nl();}
  else if(this->code==CD_JUMP)
  {ot("b ");printlab(this->arg);nl();}
  else if(this->code==CD_TESTJUMP)
  {ot("cbz x0, ");printlab(this->arg);nl();}
  else if(this->code==CD_TESTNEJUMP)
  {ot("cbnz x0, ");printlab(this->arg);nl();}
  else if(this->code==CD_NEG)
  ol("neg x0, x0");
  else if(this->code==CD_LNOT)
  {ol("cmp x0, #0");ol("cset x0, eq");}
  else if(this->code==CD_BNOT)
  ol("mvn x0, x0");
  else if(this->code==CD_EQ)armcmpset(this,"eq");
  else if(this->code==CD_NEQ)armcmpset(this,"ne");
  else if(this->code==CD_ZGE)armcmpset(this,"ge");
  else if(this->code==CD_UGE)armcmpset(this,"hs");
  else if(this->code==CD_ZLE)armcmpset(this,"le");
  else if(this->code==CD_ULE)armcmpset(this,"ls");
  else if(this->code==CD_ZLT)armcmpset(this,"lt");
  else if(this->code==CD_ULT)armcmpset(this,"lo");
  else if(this->code==CD_ZGT)armcmpset(this,"gt");
  else if(this->code==CD_UGT)armcmpset(this,"hi");
  else if(this->code==CD_BOR2REGS)op3("orr ","x0","x0",r2nd(this));
  else if(this->code==CD_BXOR2REGS)op3("eor ","x0","x0",r2nd(this));
  else if(this->code==CD_BAND2REGS)op3("and ","x0","x0",r2nd(this));
  else if(this->code==CD_ADD2REGS)op3("add ","x0","x0",r2nd(this));
  else if(this->code==CD_SUB2REGS)op3("sub ","x0",r2nd(this),"x0");   /* left-right */
  else if(this->code==CD_MUL2REGS)op3("mul ","x0","x0",r2nd(this));
  else if(this->code==CD_DIV2REGS)op3("sdiv ","x0",r2nd(this),"x0");  /* left/right */
  else if(this->code==CD_MOD2REGS)                                    /* left%right */
  {op3("sdiv ","x9",r2nd(this),"x0");ot("msub x0, x9, x0, ");outstr(r2nd(this));nl();}
  else if(this->code==CD_STKENTER)
  {ol("stp x29, x30, [sp, #-16]!");ol("mov x29, sp");}
  else if(this->code==CD_STKLEAVE)
  {ol("mov sp, x29");ol("ldp x29, x30, [sp], #16");}
  else if(this->code==CD_INCREG)
  {if(this->arg>0)addimm_arm64("x0","x0",this->arg);}
  else if(this->code==CD_DECREG)
  {if(this->arg>0)addimm_arm64("x0","x0",-this->arg);}
  else if(this->code==CD_MODSTK)
  {
    var int:a;
    a=this->arg;if(a<0)a=-a;
    a=(a+15)/16*16;   /* keep sp 16-byte aligned */
    if(this->arg>0)spadjust_arm64(a,1);
    else if(this->arg<0)spadjust_arm64(a,0);
  }
  else if(this->code==CD_SHL)op3("lsl ","x0",r2nd(this),"x0");
  else if(this->code==CD_ASR)op3("asr ","x0",r2nd(this),"x0");
  else if(this->code==CD_SHR)op3("lsr ","x0",r2nd(this),"x0");
  else if(this->code==CD_MULREG)xmulreg_arm64(this->arg,this->reg[regnames]);
  else if(this->code==CD_DIVCONST)xdivconst_arm64(this->arg);
  else if(this->code==CD_PUSH)ol("str x0, [sp, #-16]!");
  else if(this->code==CD_POP)ol("ldr x1, [sp], #16");
  else if(this->code==CD_MOVAD)ol("mov x1, x0");
  else if(this->code==CD_MOVR)   /* dst, src */
  movins("mov ",regnames[this->reg],regnames[this->arg]);
  else if(this->code==CD_RET)ol("ret");
  else if(this->code==CD_LDLIT)litaddr_arm64(regnames[this->reg],this->arg);
  else if(this->code==CD_LDN)loadimm_arm64(regnames[this->reg],this->arg);
  else if(this->code==CD_LDA)gaddr_arm64(regnames[this->reg],this->str,this->arg);
  else if(this->code==CD_LEA)addimm_arm64(regnames[this->reg],"x29",this->arg);
  else if(this->code==CD_STOW)
  {gaddr_arm64("x9",this->str,this->arg);ol("str x0, [x9]");}
  else if(this->code==CD_STOB)
  {gaddr_arm64("x9",this->str,this->arg);ol("strb w0, [x9]");}
  else if(this->code==CD_STOW2)ptrmem_arm64("str","x0","x1",this->arg);
  else if(this->code==CD_STOB2)ptrmem_arm64("strb","w0","x1",this->arg);
  else if(this->code==CD_STLW)framemem_arm64("str","x0",this->arg);
  else if(this->code==CD_STLB)framemem_arm64("strb","w0",this->arg);
  else if(this->code==CD_LBRB)ptrmem_arm64("ldrsb","x0","x0",this->arg);
  else if(this->code==CD_LBRW)ptrmem_arm64("ldr","x0","x0",this->arg);
  else if(this->code==CD_LBRA)addimm_arm64("x0","x0",this->arg);
  else if(this->code==CD_LDW)
  {gaddr_arm64("x9",this->str,this->arg);ot("ldr ");outstr(regnames[this->reg]);outstr(", [x9]");nl();}
  else if(this->code==CD_LDB)
  {gaddr_arm64("x9",this->str,this->arg);ot("ldrsb ");outstr(regnames[this->reg]);outstr(", [x9]");nl();}
  else if(this->code==CD_LDLW)framemem_arm64("ldr",regnames[this->reg],this->arg);
  else if(this->code==CD_LDLB)framemem_arm64("ldrsb",regnames[this->reg],this->arg);
  /* ---- AArch64 floating point: d0 = FP accumulator, d1 = 2nd operand ------ */
  else if(this->code==CD_FLDLIT)
  {
    /* add :lo12: (unscaled reloc) then ldr -- the scaled ldr lo12 form would
       require the .double pool to be 8-byte aligned, which it isn't. */
    ot("adrp x9, .LF");outdec(this->arg);nl();
    ot("add x9, x9, #:lo12:.LF");outdec(this->arg);nl();
    ol("ldr d0, [x9]");
  }
  else if(this->code==CD_F2I)ol("fcvtzs x0, d0");   /* double->int, truncate */
  else if(this->code==CD_FLDLOC)framemem_arm64("ldr","d0",this->arg);
  else if(this->code==CD_FLDGLB)
  {gaddr_arm64("x9",this->str,this->arg);ol("ldr d0, [x9]");}
  else if(this->code==CD_FSTLOC)framemem_arm64("str","d0",this->arg);
  else if(this->code==CD_FSTGLB)
  {gaddr_arm64("x9",this->str,this->arg);ol("str d0, [x9]");}
  else if(this->code==CD_FPUSH)ol("str d0, [sp, #-16]!");
  else if(this->code==CD_FPOP)ol("ldr d1, [sp], #16");
  else if(this->code==CD_FADD)ol("fadd d0, d1, d0");
  else if(this->code==CD_FSUB)ol("fsub d0, d1, d0");   /* left-right */
  else if(this->code==CD_FMUL)ol("fmul d0, d1, d0");
  else if(this->code==CD_FDIV)ol("fdiv d0, d1, d0");   /* left/right */
  else if(this->code==CD_I2F)ol("scvtf d0, x0");       /* promote right */
  else if(this->code==CD_I2F1)ol("scvtf d1, x1");      /* promote left */
  else if(this->code==CD_MARGINT)
  ptrmem_arm64("ldr",argreg_arm64(this->reg),"sp",this->arg);
  else if(this->code==CD_MARGFP)
  ptrmem_arm64("ldr",fpargreg_arm64(this->reg),"sp",this->arg);
  else if(this->code==CD_SARGINT)
  framemem_arm64("str",argreg_arm64(this->reg),this->arg);
  else if(this->code==CD_SARGFP)
  framemem_arm64("str",fpargreg_arm64(this->reg),this->arg);
  else if(this->code==CD_FLDLOCS)            /* 4-byte float: load + widen */
  {framemem_arm64("ldr","s0",this->arg);ol("fcvt d0, s0");}
  else if(this->code==CD_FLDGLBS)
  {gaddr_arm64("x9",this->str,this->arg);ol("ldr s0, [x9]");ol("fcvt d0, s0");}
  else if(this->code==CD_FSTLOCS)            /* narrow into s1 (preserve d0) */
  {ol("fcvt s1, d0");framemem_arm64("str","s1",this->arg);}
  else if(this->code==CD_FSTGLBS)
  {ol("fcvt s1, d0");gaddr_arm64("x9",this->str,this->arg);ol("str s1, [x9]");}
  else if(this->code==CD_FLBR)ptrmem_arm64("ldr","d0","x0",this->arg);
  else if(this->code==CD_FLBRS)
  {ptrmem_arm64("ldr","s0","x0",this->arg);ol("fcvt d0, s0");}
  else if(this->code==CD_FSTBR2)ptrmem_arm64("str","d0","x1",this->arg);
  else if(this->code==CD_FSTBR2S)
  {ol("fcvt s1, d0");ptrmem_arm64("str","s1","x1",this->arg);}
  else if(this->code==CD_IGNORE)
  ;
  else
  {fprintf(stderr,"%d ",this->code);error("unknown opcode (arm64)");}
}
/* ===================== RISC-V (RV64) backend (M3) ==========================
   a0 = accumulator (RG_A), a1 = 2nd operand (RG_D), t0/t1 = scratch, s0/fp =
   frame pointer, sp = stack, ra = return address. Load/store machine with NO
   condition flags: comparisons synthesise a 0/1 with slt/seqz/snez/xori, and
   the test-and-branch opcodes use beqz/bnez. `li` assembles any immediate
   (so loadimm needs no chunking). Integer/pointer only -- FP errors cleanly. */
func riscvarg(i:int)   /* RV64 integer argument registers a0..a7 */
{
  if(i==0)return "a0";
  else if(i==1)return "a1";
  else if(i==2)return "a2";
  else if(i==3)return "a3";
  else if(i==4)return "a4";
  else if(i==5)return "a5";
  else if(i==6)return "a6";
  else if(i==7)return "a7";
  error("riscv: more than 8 register arguments not supported");
  return "a0";
}
func addimm_riscv(dst:*char,src:*char,val:int)
{
  /* dst = src + val; addi has a 12-bit signed immediate, scratch t0 for big */
  if((val>=(0-2048))&&(val<2048))
  {ot("addi ");outstr(dst);outstr(", ");outstr(src);outstr(", ");outdec(val);nl();}
  else
  {
    ot("li t0, ");outdec(val);nl();
    ot("add ");outstr(dst);outstr(", ");outstr(src);outstr(", t0");nl();
  }
}
func gaddr_riscv(reg:*char,name:*char,off:int)
{
  /* reg = &name[+off]; `la` adapts to the code model (non-PIC static here) */
  ot("la ");outstr(reg);outstr(", ");outname(name);nl();
  if(off)addimm_riscv(reg,reg,off);
}
func framemem_riscv(op:*char,reg:*char,off:int)
{
  /* op reg, off(s0); compute the address in t0 when off exceeds 12 bits */
  if((off>=(0-2048))&&(off<2048))
  {ot(op);outstr(" ");outstr(reg);outstr(", ");outdec(off);outstr("(s0)");nl();}
  else
  {addimm_riscv("t0","s0",off);ot(op);outstr(" ");outstr(reg);outstr(", 0(t0)");nl();}
}
func ptrmem_riscv(op:*char,reg:*char,base:*char,off:int)
{
  if((off>=(0-2048))&&(off<2048))
  {ot(op);outstr(" ");outstr(reg);outstr(", ");outdec(off);outstr("(");outstr(base);outstr(")");nl();}
  else
  {addimm_riscv("t0",base,off);ot(op);outstr(" ");outstr(reg);outstr(", 0(t0)");nl();}
}
func xmulreg_riscv(k:int,s:*char)
{
  var int:l;
  if(k==1)return ;
  if(k==0){ot("li ");outstr(s);outstr(", 0");nl();return ;}
  l=1;
  while(l<31)if(k==(1<<l))
  {ot("slli ");outstr(s);outstr(", ");outstr(s);outstr(", ");outdec(l);nl();return ;}
  else l++;
  ot("li t0, ");outdec(k);nl();
  ot("mul ");outstr(s);outstr(", ");outstr(s);outstr(", t0");nl();
}
func xdivconst_riscv(k:int)
{
  var int:l;
  if(k==1)return ;
  if(!k){error("division by zero");return ;}
  l=1;
  while(l<31)if(k==(1<<l))
  {ot("srai a0, a0, ");outdec(l);nl();return ;}
  else l++;
  ot("li t0, ");outdec(k);nl();
  ol("div a0, a0, t0");
}
func cd_write_riscv(*scode:this)
{
  if(this->code==CD_ZCALL)
  {
    /* RV64 callee sign-extends a 32-bit int return to 64 bits per the psABI, so
       getchar/fgetc need no fixup (unlike the x86_64 cltq). */
    ot("call ");outname(this->str);nl();
  }
  else if(this->code==CD_SPILLARGS)
  {
    var int:i;
    for(i=0;i<this->arg;i++)
    framemem_riscv("sd",riscvarg(i),-(i+1)*target.wordsize);
  }
  else if(this->code==CD_MARSHAL)
  {
    var int:i;
    for(i=0;i<this->arg;i++)
    ptrmem_riscv("ld",riscvarg(i),"sp",i*target.stackslot);
  }
  else if(this->code==CD_LAB)
  {printlab(this->arg);col();nl();}
  else if(this->code==CD_JUMP)
  {ot("j ");printlab(this->arg);nl();}
  else if(this->code==CD_TESTJUMP)
  {ot("beqz a0, ");printlab(this->arg);nl();}
  else if(this->code==CD_TESTNEJUMP)
  {ot("bnez a0, ");printlab(this->arg);nl();}
  else if(this->code==CD_NEG)ol("neg a0, a0");
  else if(this->code==CD_LNOT)ol("seqz a0, a0");
  else if(this->code==CD_BNOT)ol("not a0, a0");
  /* compares: 2nd operand (left) = r2nd, a0 = right; result 0/1 in a0 */
  else if(this->code==CD_EQ){op3("xor ","a0",r2nd(this),"a0");ol("seqz a0, a0");}
  else if(this->code==CD_NEQ){op3("xor ","a0",r2nd(this),"a0");ol("snez a0, a0");}
  else if(this->code==CD_ZLT)op3("slt ","a0",r2nd(this),"a0");
  else if(this->code==CD_ULT)op3("sltu ","a0",r2nd(this),"a0");
  else if(this->code==CD_ZGT)op3("slt ","a0","a0",r2nd(this));
  else if(this->code==CD_UGT)op3("sltu ","a0","a0",r2nd(this));
  else if(this->code==CD_ZLE){op3("slt ","a0","a0",r2nd(this));ol("xori a0, a0, 1");}
  else if(this->code==CD_ULE){op3("sltu ","a0","a0",r2nd(this));ol("xori a0, a0, 1");}
  else if(this->code==CD_ZGE){op3("slt ","a0",r2nd(this),"a0");ol("xori a0, a0, 1");}
  else if(this->code==CD_UGE){op3("sltu ","a0",r2nd(this),"a0");ol("xori a0, a0, 1");}
  else if(this->code==CD_BOR2REGS)op3("or ","a0","a0",r2nd(this));
  else if(this->code==CD_BXOR2REGS)op3("xor ","a0","a0",r2nd(this));
  else if(this->code==CD_BAND2REGS)op3("and ","a0","a0",r2nd(this));
  else if(this->code==CD_ADD2REGS)op3("add ","a0","a0",r2nd(this));
  else if(this->code==CD_SUB2REGS)op3("sub ","a0",r2nd(this),"a0");   /* left-right */
  else if(this->code==CD_MUL2REGS)op3("mul ","a0","a0",r2nd(this));
  else if(this->code==CD_DIV2REGS)op3("div ","a0",r2nd(this),"a0");   /* left/right */
  else if(this->code==CD_MOD2REGS)op3("rem ","a0",r2nd(this),"a0");   /* left%right */
  else if(this->code==CD_STKENTER)
  {
    /* save ra+fp, set s0 to point at the saved fp (like %rbp): saved fp at
       0(s0), saved ra at 8(s0), incoming stack args at 16(s0). */
    ol("addi sp, sp, -16");
    ol("sd s0, 0(sp)");
    ol("sd ra, 8(sp)");
    ol("mv s0, sp");
  }
  else if(this->code==CD_STKLEAVE)
  {
    ol("mv sp, s0");
    ol("ld s0, 0(sp)");
    ol("ld ra, 8(sp)");
    ol("addi sp, sp, 16");
  }
  else if(this->code==CD_INCREG)
  {if(this->arg>0)addimm_riscv("a0","a0",this->arg);}
  else if(this->code==CD_DECREG)
  {if(this->arg>0)addimm_riscv("a0","a0",-this->arg);}
  else if(this->code==CD_MODSTK)
  {if(this->arg)addimm_riscv("sp","sp",this->arg);}
  else if(this->code==CD_SHL)op3("sll ","a0",r2nd(this),"a0");
  else if(this->code==CD_ASR)op3("sra ","a0",r2nd(this),"a0");
  else if(this->code==CD_SHR)op3("srl ","a0",r2nd(this),"a0");
  else if(this->code==CD_MULREG)xmulreg_riscv(this->arg,this->reg[regnames]);
  else if(this->code==CD_DIVCONST)xdivconst_riscv(this->arg);
  else if(this->code==CD_PUSH){ol("addi sp, sp, -8");ol("sd a0, 0(sp)");}
  else if(this->code==CD_POP){ol("ld a1, 0(sp)");ol("addi sp, sp, 8");}
  else if(this->code==CD_MOVAD)ol("mv a1, a0");
  else if(this->code==CD_MOVR)   /* dst, src */
  movins("mv ",regnames[this->reg],regnames[this->arg]);
  else if(this->code==CD_RET)ol("ret");
  else if(this->code==CD_LDLIT)   /* address of string-literal pool + offset */
  {ot("la ");outstr(regnames[this->reg]);outstr(", ");printlab(stlab);nl();
   if(this->arg)addimm_riscv(regnames[this->reg],regnames[this->reg],this->arg);}
  else if(this->code==CD_LDN)
  {ot("li ");outstr(regnames[this->reg]);outstr(", ");outdec(this->arg);nl();}
  else if(this->code==CD_LDA)gaddr_riscv(regnames[this->reg],this->str,this->arg);
  else if(this->code==CD_LEA)addimm_riscv(regnames[this->reg],"s0",this->arg);
  else if(this->code==CD_STOW)
  {gaddr_riscv("t0",this->str,this->arg);ol("sd a0, 0(t0)");}
  else if(this->code==CD_STOB)
  {gaddr_riscv("t0",this->str,this->arg);ol("sb a0, 0(t0)");}
  else if(this->code==CD_STOW2)ptrmem_riscv("sd","a0","a1",this->arg);
  else if(this->code==CD_STOB2)ptrmem_riscv("sb","a0","a1",this->arg);
  else if(this->code==CD_STLW)framemem_riscv("sd","a0",this->arg);
  else if(this->code==CD_STLB)framemem_riscv("sb","a0",this->arg);
  else if(this->code==CD_LBRB)ptrmem_riscv("lb","a0","a0",this->arg);
  else if(this->code==CD_LBRW)ptrmem_riscv("ld","a0","a0",this->arg);
  else if(this->code==CD_LBRA)addimm_riscv("a0","a0",this->arg);
  else if(this->code==CD_LDW)
  {gaddr_riscv("t0",this->str,this->arg);ot("ld ");outstr(regnames[this->reg]);outstr(", 0(t0)");nl();}
  else if(this->code==CD_LDB)
  {gaddr_riscv("t0",this->str,this->arg);ot("lb ");outstr(regnames[this->reg]);outstr(", 0(t0)");nl();}
  else if(this->code==CD_LDLW)framemem_riscv("ld",regnames[this->reg],this->arg);
  else if(this->code==CD_LDLB)framemem_riscv("lb",regnames[this->reg],this->arg);
  /* ---- RV64 floating point (D ext): fa0 = accumulator, fa1 = 2nd operand --- */
  else if(this->code==CD_FLDLIT)
  {ot("la t0, .LF");outdec(this->arg);nl();ol("fld fa0, 0(t0)");}
  else if(this->code==CD_F2I)ol("fcvt.l.d a0, fa0, rtz");   /* double->long, trunc */
  else if(this->code==CD_FLDLOC)framemem_riscv("fld","fa0",this->arg);
  else if(this->code==CD_FLDGLB)
  {gaddr_riscv("t0",this->str,this->arg);ol("fld fa0, 0(t0)");}
  else if(this->code==CD_FSTLOC)framemem_riscv("fsd","fa0",this->arg);
  else if(this->code==CD_FSTGLB)
  {gaddr_riscv("t0",this->str,this->arg);ol("fsd fa0, 0(t0)");}
  else if(this->code==CD_FPUSH){ol("addi sp, sp, -8");ol("fsd fa0, 0(sp)");}
  else if(this->code==CD_FPOP){ol("fld fa1, 0(sp)");ol("addi sp, sp, 8");}
  else if(this->code==CD_FADD)ol("fadd.d fa0, fa1, fa0");
  else if(this->code==CD_FSUB)ol("fsub.d fa0, fa1, fa0");   /* left-right */
  else if(this->code==CD_FMUL)ol("fmul.d fa0, fa1, fa0");
  else if(this->code==CD_FDIV)ol("fdiv.d fa0, fa1, fa0");   /* left/right */
  else if(this->code==CD_I2F)ol("fcvt.d.l fa0, a0");        /* promote right */
  else if(this->code==CD_I2F1)ol("fcvt.d.l fa1, a1");       /* promote left */
  else if(this->code==CD_FLDLOCS)            /* 4-byte float: load + widen */
  {framemem_riscv("flw","ft0",this->arg);ol("fcvt.d.s fa0, ft0");}
  else if(this->code==CD_FLDGLBS)
  {gaddr_riscv("t0",this->str,this->arg);ol("flw ft0, 0(t0)");ol("fcvt.d.s fa0, ft0");}
  else if(this->code==CD_FSTLOCS)            /* narrow into ft0 (preserve fa0) */
  {ol("fcvt.s.d ft0, fa0");framemem_riscv("fsw","ft0",this->arg);}
  else if(this->code==CD_FSTGLBS)
  {ol("fcvt.s.d ft0, fa0");gaddr_riscv("t0",this->str,this->arg);ol("fsw ft0, 0(t0)");}
  else if(this->code==CD_FLBR)ptrmem_riscv("fld","fa0","a0",this->arg);
  else if(this->code==CD_FLBRS)
  {ptrmem_riscv("flw","ft0","a0",this->arg);ol("fcvt.d.s fa0, ft0");}
  else if(this->code==CD_FSTBR2)ptrmem_riscv("fsd","fa0","a1",this->arg);
  else if(this->code==CD_FSTBR2S)
  {ol("fcvt.s.d ft0, fa0");ptrmem_riscv("fsw","ft0","a1",this->arg);}
  else if((this->code>=CD_FLDLIT)&&(this->code<=CD_FSTBR2S))
  error("riscv: this FP opcode is not used (FP args go in integer registers)");
  else if(this->code==CD_IGNORE)
  ;
  else
  {fprintf(stderr,"%d ",this->code);error("unknown opcode (riscv)");}
}
/* ---- MIPS64 (N64 ABI, big-endian) integer backend --------------------------
   Mirrors cd_write_riscv: a load/store machine with slt-style compares and no
   condition flags. $2 = accumulator (RG_A), $3 = 2nd operand (RG_D); $12/$13
   are address/immediate scratch (never IR destinations); $4..$11 carry args;
   $fp is the frame pointer, $sp/$ra as usual. N64 is LP64 (int==ptr==8 bytes)
   so all arithmetic uses the d-prefixed 64-bit instructions. The assembler runs
   in its default `.set reorder` mode, so it fills branch delay slots for us. */
func mipsarg(i:int)   /* N64 integer argument registers $a0..$a7 == $4..$11 */
{
  if(i==0)return "$4";
  else if(i==1)return "$5";
  else if(i==2)return "$6";
  else if(i==3)return "$7";
  else if(i==4)return "$8";
  else if(i==5)return "$9";
  else if(i==6)return "$10";
  else if(i==7)return "$11";
  error("mips: more than 8 register arguments not supported");
  return "$4";
}
func addimm_mips(dst:*char,src:*char,val:int)
{
  /* dst = src + val; daddiu has a 16-bit signed immediate. For bigger values
     load into $13 first (a scratch distinct from the $12 address scratch, so
     this stays correct even when dst==src==$12, as in gaddr_mips). */
  if((val>=(0-32768))&&(val<32768))
  {ot("daddiu ");outstr(dst);outstr(", ");outstr(src);outstr(", ");outdec(val);nl();}
  else
  {
    ot("li $13, ");outdec(val);nl();
    ot("daddu ");outstr(dst);outstr(", ");outstr(src);outstr(", $13");nl();
  }
}
func gaddr_mips(reg:*char,name:*char,off:int)
{
  /* reg = &name[+off]; `dla` forms the full 64-bit absolute address (non-PIC) */
  ot("dla ");outstr(reg);outstr(", ");outname(name);nl();
  if(off)addimm_mips(reg,reg,off);
}
func framemem_mips(op:*char,reg:*char,off:int)
{
  /* op reg, off($fp); compute the address in $12 when off exceeds 16 bits */
  if((off>=(0-32768))&&(off<32768))
  {ot(op);outstr(" ");outstr(reg);outstr(", ");outdec(off);outstr("($fp)");nl();}
  else
  {addimm_mips("$12","$fp",off);ot(op);outstr(" ");outstr(reg);outstr(", 0($12)");nl();}
}
func ptrmem_mips(op:*char,reg:*char,base:*char,off:int)
{
  if((off>=(0-32768))&&(off<32768))
  {ot(op);outstr(" ");outstr(reg);outstr(", ");outdec(off);outstr("(");outstr(base);outstr(")");nl();}
  else
  {addimm_mips("$12",base,off);ot(op);outstr(" ");outstr(reg);outstr(", 0($12)");nl();}
}
func xmulreg_mips(k:int,s:*char)
{
  var int:l;
  if(k==1)return ;
  if(k==0){ot("li ");outstr(s);outstr(", 0");nl();return ;}
  l=1;
  while(l<31)if(k==(1<<l))
  {ot("dsll ");outstr(s);outstr(", ");outstr(s);outstr(", ");outdec(l);nl();return ;}
  else l++;
  ot("li $12, ");outdec(k);nl();
  ot("dmul ");outstr(s);outstr(", ");outstr(s);outstr(", $12");nl();
}
func xdivconst_mips(k:int)
{
  var int:l;
  if(k==1)return ;
  if(!k){error("division by zero");return ;}
  l=1;
  while(l<31)if(k==(1<<l))
  {ot("dsra $2, $2, ");outdec(l);nl();return ;}
  else l++;
  ot("li $12, ");outdec(k);nl();
  ol("ddiv $2, $2, $12");
}
func cd_write_mips(*scode:this)
{
  if(this->code==CD_ZCALL)
  {
    /* Call through $t9 ($25): the MIPS PIC convention requires the callee's
       address to be in $t9 at entry, because glibc's PIC functions recompute
       their own $gp from it (gp = t9 + gp_offset). A plain `jal name` leaves
       $t9 garbage, so e.g. malloc then dereferences a wrong-$gp GOT slot and
       crashes. Our own (non-PIC) functions ignore $t9, so this is uniform.
       N64 sign-extends a 32-bit int return in $v0 per the psABI, so getchar/
       fgetc need no fixup (like riscv, unlike the x86_64 cltq). */
    ot("dla $25, ");outname(this->str);nl();
    ol("jalr $25");
  }
  else if(this->code==CD_SPILLARGS)
  {
    var int:i;
    for(i=0;i<this->arg;i++)
    framemem_mips("sd",mipsarg(i),-(i+1)*target.wordsize);
  }
  else if(this->code==CD_MARSHAL)
  {
    var int:i;
    for(i=0;i<this->arg;i++)
    ptrmem_mips("ld",mipsarg(i),"$sp",i*target.stackslot);
  }
  else if(this->code==CD_LAB)
  {printlab(this->arg);col();nl();}
  else if(this->code==CD_JUMP)
  {ot("b ");printlab(this->arg);nl();}
  else if(this->code==CD_TESTJUMP)
  {ot("beqz $2, ");printlab(this->arg);nl();}
  else if(this->code==CD_TESTNEJUMP)
  {ot("bnez $2, ");printlab(this->arg);nl();}
  else if(this->code==CD_NEG)ol("dsubu $2, $0, $2");
  else if(this->code==CD_LNOT)ol("sltiu $2, $2, 1");
  else if(this->code==CD_BNOT)ol("nor $2, $2, $0");
  /* compares: 2nd operand (left) = r2nd, $2 = right; result 0/1 in $2 */
  else if(this->code==CD_EQ){op3("xor ","$2",r2nd(this),"$2");ol("sltiu $2, $2, 1");}
  else if(this->code==CD_NEQ){op3("xor ","$2",r2nd(this),"$2");ol("sltu $2, $0, $2");}
  else if(this->code==CD_ZLT)op3("slt ","$2",r2nd(this),"$2");
  else if(this->code==CD_ULT)op3("sltu ","$2",r2nd(this),"$2");
  else if(this->code==CD_ZGT)op3("slt ","$2","$2",r2nd(this));
  else if(this->code==CD_UGT)op3("sltu ","$2","$2",r2nd(this));
  else if(this->code==CD_ZLE){op3("slt ","$2","$2",r2nd(this));ol("xori $2, $2, 1");}
  else if(this->code==CD_ULE){op3("sltu ","$2","$2",r2nd(this));ol("xori $2, $2, 1");}
  else if(this->code==CD_ZGE){op3("slt ","$2",r2nd(this),"$2");ol("xori $2, $2, 1");}
  else if(this->code==CD_UGE){op3("sltu ","$2",r2nd(this),"$2");ol("xori $2, $2, 1");}
  else if(this->code==CD_BOR2REGS)op3("or ","$2","$2",r2nd(this));
  else if(this->code==CD_BXOR2REGS)op3("xor ","$2","$2",r2nd(this));
  else if(this->code==CD_BAND2REGS)op3("and ","$2","$2",r2nd(this));
  else if(this->code==CD_ADD2REGS)op3("daddu ","$2","$2",r2nd(this));
  else if(this->code==CD_SUB2REGS)op3("dsubu ","$2",r2nd(this),"$2");   /* left-right */
  else if(this->code==CD_MUL2REGS)op3("dmul ","$2","$2",r2nd(this));
  else if(this->code==CD_DIV2REGS)op3("ddiv ","$2",r2nd(this),"$2");    /* left/right */
  else if(this->code==CD_MOD2REGS)op3("drem ","$2",r2nd(this),"$2");    /* left%right */
  else if(this->code==CD_STKENTER)
  {
    /* save ra+fp, point $fp at the saved fp (like %rbp): saved fp at 0($fp),
       saved ra at 8($fp), incoming stack args at 16($fp). */
    ol("daddiu $sp, $sp, -16");
    ol("sd $fp, 0($sp)");
    ol("sd $ra, 8($sp)");
    ol("move $fp, $sp");
  }
  else if(this->code==CD_STKLEAVE)
  {
    ol("move $sp, $fp");
    ol("ld $fp, 0($sp)");
    ol("ld $ra, 8($sp)");
    ol("daddiu $sp, $sp, 16");
  }
  else if(this->code==CD_INCREG)
  {if(this->arg>0)addimm_mips("$2","$2",this->arg);}
  else if(this->code==CD_DECREG)
  {if(this->arg>0)addimm_mips("$2","$2",-this->arg);}
  else if(this->code==CD_MODSTK)
  {if(this->arg)addimm_mips("$sp","$sp",this->arg);}
  else if(this->code==CD_SHL)op3("dsllv ","$2",r2nd(this),"$2");
  else if(this->code==CD_ASR)op3("dsrav ","$2",r2nd(this),"$2");
  else if(this->code==CD_SHR)op3("dsrlv ","$2",r2nd(this),"$2");
  else if(this->code==CD_MULREG)xmulreg_mips(this->arg,regnames[this->reg]);
  else if(this->code==CD_DIVCONST)xdivconst_mips(this->arg);
  else if(this->code==CD_PUSH){ol("daddiu $sp, $sp, -8");ol("sd $2, 0($sp)");}
  else if(this->code==CD_POP){ol("ld $3, 0($sp)");ol("daddiu $sp, $sp, 8");}
  else if(this->code==CD_MOVAD)ol("move $3, $2");
  else if(this->code==CD_MOVR)   /* dst, src */
  movins("move ",regnames[this->reg],regnames[this->arg]);
  else if(this->code==CD_RET)ol("jr $ra");
  else if(this->code==CD_LDLIT)   /* address of string-literal pool + offset */
  {ot("dla ");outstr(regnames[this->reg]);outstr(", ");printlab(stlab);nl();
   if(this->arg)addimm_mips(regnames[this->reg],regnames[this->reg],this->arg);}
  else if(this->code==CD_LDN)
  {ot("li ");outstr(regnames[this->reg]);outstr(", ");outdec(this->arg);nl();}
  else if(this->code==CD_LDA)gaddr_mips(regnames[this->reg],this->str,this->arg);
  else if(this->code==CD_LEA)addimm_mips(regnames[this->reg],"$fp",this->arg);
  else if(this->code==CD_STOW)
  {gaddr_mips("$12",this->str,this->arg);ol("sd $2, 0($12)");}
  else if(this->code==CD_STOB)
  {gaddr_mips("$12",this->str,this->arg);ol("sb $2, 0($12)");}
  else if(this->code==CD_STOW2)ptrmem_mips("sd","$2","$3",this->arg);
  else if(this->code==CD_STOB2)ptrmem_mips("sb","$2","$3",this->arg);
  else if(this->code==CD_STLW)framemem_mips("sd","$2",this->arg);
  else if(this->code==CD_STLB)framemem_mips("sb","$2",this->arg);
  else if(this->code==CD_LBRB)ptrmem_mips("lb","$2","$2",this->arg);
  else if(this->code==CD_LBRW)ptrmem_mips("ld","$2","$2",this->arg);
  else if(this->code==CD_LBRA)addimm_mips("$2","$2",this->arg);
  else if(this->code==CD_LDW)
  {gaddr_mips("$12",this->str,this->arg);ot("ld ");outstr(regnames[this->reg]);outstr(", 0($12)");nl();}
  else if(this->code==CD_LDB)
  {gaddr_mips("$12",this->str,this->arg);ot("lb ");outstr(regnames[this->reg]);outstr(", 0($12)");nl();}
  else if(this->code==CD_LDLW)framemem_mips("ld",regnames[this->reg],this->arg);
  else if(this->code==CD_LDLB)framemem_mips("lb",regnames[this->reg],this->arg);
  /* ---- MIPS64 floating point (N64, hard-float): $f0 = accumulator (also the
     N64 double return reg, so `return d` needs no move), $f2 = 2nd operand,
     $f4 = scratch for the 4-byte-float widen/narrow. FP args are passed as raw
     bits in the integer registers (the N64 variadic convention -- what printf
     reads), so they reuse the integer marshaling; the double return is $f0. */
  else if(this->code==CD_FLDLIT)
  {ot("dla $12, .LF");outdec(this->arg);nl();ol("ldc1 $f0, 0($12)");}
  else if(this->code==CD_F2I){ol("trunc.l.d $f0, $f0");ol("dmfc1 $2, $f0");} /* double->long, trunc */
  else if(this->code==CD_FLDLOC)framemem_mips("ldc1","$f0",this->arg);
  else if(this->code==CD_FLDGLB)
  {gaddr_mips("$12",this->str,this->arg);ol("ldc1 $f0, 0($12)");}
  else if(this->code==CD_FSTLOC)framemem_mips("sdc1","$f0",this->arg);
  else if(this->code==CD_FSTGLB)
  {gaddr_mips("$12",this->str,this->arg);ol("sdc1 $f0, 0($12)");}
  else if(this->code==CD_FPUSH){ol("daddiu $sp, $sp, -8");ol("sdc1 $f0, 0($sp)");}
  else if(this->code==CD_FPOP){ol("ldc1 $f2, 0($sp)");ol("daddiu $sp, $sp, 8");}
  else if(this->code==CD_FADD)ol("add.d $f0, $f2, $f0");
  else if(this->code==CD_FSUB)ol("sub.d $f0, $f2, $f0");   /* left-right */
  else if(this->code==CD_FMUL)ol("mul.d $f0, $f2, $f0");
  else if(this->code==CD_FDIV)ol("div.d $f0, $f2, $f0");   /* left/right */
  else if(this->code==CD_I2F){ol("dmtc1 $2, $f0");ol("cvt.d.l $f0, $f0");}  /* promote right */
  else if(this->code==CD_I2F1){ol("dmtc1 $3, $f2");ol("cvt.d.l $f2, $f2");} /* promote left */
  else if(this->code==CD_FLDLOCS)            /* 4-byte float: load + widen */
  {framemem_mips("lwc1","$f4",this->arg);ol("cvt.d.s $f0, $f4");}
  else if(this->code==CD_FLDGLBS)
  {gaddr_mips("$12",this->str,this->arg);ol("lwc1 $f4, 0($12)");ol("cvt.d.s $f0, $f4");}
  else if(this->code==CD_FSTLOCS)            /* narrow into $f4 (preserve $f0) */
  {ol("cvt.s.d $f4, $f0");framemem_mips("swc1","$f4",this->arg);}
  else if(this->code==CD_FSTGLBS)
  {ol("cvt.s.d $f4, $f0");gaddr_mips("$12",this->str,this->arg);ol("swc1 $f4, 0($12)");}
  else if(this->code==CD_FLBR)ptrmem_mips("ldc1","$f0","$2",this->arg);
  else if(this->code==CD_FLBRS)
  {ptrmem_mips("lwc1","$f4","$2",this->arg);ol("cvt.d.s $f0, $f4");}
  else if(this->code==CD_FSTBR2)ptrmem_mips("sdc1","$f0","$3",this->arg);
  else if(this->code==CD_FSTBR2S)
  {ol("cvt.s.d $f4, $f0");ptrmem_mips("swc1","$f4","$3",this->arg);}
  else if((this->code>=CD_FLDLIT)&&(this->code<=CD_FSTBR2S))
  error("mips: this FP opcode is not used (FP args go in integer registers)");
  else if(this->code==CD_IGNORE)
  ;
  else
  {fprintf(stderr,"%d ",this->code);error("unknown opcode (mips)");}
}
func cd_write_i386(*scode:this)
{
  if(this->code==CD_ZCALL)
  {
    ot("call ");
    outname(this->str);
    nl();
  }
  else if(this->code==CD_LAB)
  {
    printlab(this->arg);
    col();
    nl();
  }
  else if(this->code==CD_JUMP)
  {
    ot("jmp ");
    printlab(this->arg);
    nl();
  }
  else if(this->code==CD_TESTJUMP)
  {
    ol("testl %eax, %eax");
    ot("je");
    tab();
    printlab(this->arg);
    nl();
  }
  else if(this->code==CD_TESTNEJUMP)
  {
    ol("testl %eax, %eax");
    ot("jne");
    tab();
    printlab(this->arg);
    nl();
  }
  else if(this->code==CD_NEG)
  {
    ol("negl %eax");
  }
  else if(this->code==CD_LNOT)
  {
    ol("testl %eax,%eax");
    ol("sete %al");
    ol("movzbl %al, %eax");
  }
  else if(this->code==CD_BNOT)
  {
    ol("notl %eax");
  }
  else if(this->code==CD_EQ)
  {
    ot("cmpl");
    ot("%eax, %edx");
    nl();
    ot("sete");
    ot("%al");
    nl();
    ot("movzbl");
    ot("%al, %eax");
    nl();
  }
  else if(this->code==CD_NEQ)
  {
    ot("cmpl");
    ot("%eax, %edx");
    nl();
    ot("setne");
    ot("%al");
    nl();
    ot("movzbl");
    ot("%al, %eax");
    nl();
  }
  else if(this->code==CD_ZGE)
  {
    ot("cmpl");
    ot("%eax, %edx");
    nl();
    ot("setge");
    ot("%al");
    nl();
    ot("movzbl");
    ot("%al, %eax");
    nl();
  }
  else if(this->code==CD_UGE)
  {
    ot("cmpl");
    ot("%eax, %edx");
    nl();
    ot("setae");
    ot("%al");
    nl();
    ot("movzbl");
    ot("%al, %eax");
    nl();
  }
  else if(this->code==CD_ZLE)
  {
    ot("cmpl");
    ot("%eax, %edx");
    nl();
    ot("setle");
    ot("%al");
    nl();
    ot("movzbl");
    ot("%al, %eax");
    nl();
  }
  else if(this->code==CD_ULE)
  {
    ot("cmpl");
    ot("%eax, %edx");
    nl();
    ot("setbe");
    ot("%al");
    nl();
    ot("movzbl");
    ot("%al, %eax");
    nl();
  }
  else if(this->code==CD_ZLT)
  {
    ot("cmpl");
    ot("%eax, %edx");
    nl();
    ot("setl");
    ot("%al");
    nl();
    ot("movzbl");
    ot("%al, %eax");
    nl();
  }
  else if(this->code==CD_ULT)
  {
    ot("cmpl");
    ot("%eax, %edx");
    nl();
    ot("setb");
    ot("%al");
    nl();
    ot("movzbl");
    ot("%al, %eax");
    nl();
  }
  else if(this->code==CD_ZGT)
  {
    ot("cmpl");
    ot("%eax, %edx");
    nl();
    ot("setg");
    ot("%al");
    nl();
    ot("movzbl");
    ot("%al, %eax");
    nl();
  }
  else if(this->code==CD_UGT)
  {
    ot("cmpl");
    ot("%eax, %edx");
    nl();
    ot("seta");
    ot("%al");
    nl();
    ot("movzbl");
    ot("%al, %eax");
    nl();
  }
  else if(this->code==CD_BOR2REGS)
  {
    ol("orl %edx, %eax");
  }
  else if(this->code==CD_BXOR2REGS)
  {
    ol("xorl %edx, %eax");
  }
  else if(this->code==CD_BAND2REGS)
  {
    ol("andl %edx, %eax");
  }
  else if(this->code==CD_ADD2REGS)
  {
    ol("addl %edx, %eax");
  }
  else if(this->code==CD_SUB2REGS)
  {
    ol("subl %eax, %edx");
    ol("movl %edx, %eax");
  }
  else if(this->code==CD_MUL2REGS)
  {
    ol("imull %edx");
  }
  else if(this->code==CD_DIV2REGS)
  {
    ol("xchgl %eax, %edx");
    ol("movl %edx, %ecx");
    ol("cltd");
    ol("idivl %ecx");
  }
  else if(this->code==CD_MOD2REGS)
  {
    ol("xchgl %eax, %edx");
    ol("movl %edx, %ecx");
    ol("cltd");
    ol("idivl %ecx");
    ol("movl %edx, %eax");
  }
  else if(this->code==CD_STKENTER)
  {
    ol("pushl %ebp");
    ol("movl %esp, %ebp");
  }
  else if(this->code==CD_STKLEAVE)
  {
    ol("movl %ebp, %esp");
    ol("popl %ebp");
  }
  else if(this->code==CD_INCREG)
  {
    if(this->arg>0)
    {
      if(this->arg<3)
      while(this->arg--)
        ol("incl %eax");
      else
      {
        ot("addl $");
        outdec(this->arg);
        outstr(", %eax");
        nl();
      }
    }
  }
  else if(this->code==CD_DECREG)
  {
    if(this->arg>0)
    {
      if(this->arg<3)
      while(this->arg--)
        ol("decl %eax");
      else
      {
        ot("subl $");
        outdec(this->arg);
        outstr(", %eax");
        nl();
      }
    }
  }
  else if(this->code==CD_MODSTK)
  {
    if(this->arg>0)
    {
      ot("addl $");
      outdec(this->arg);
      outasm(", %esp");
      nl();
    }
    else if(this->arg<0)
    {
      ot("subl $");
      outdec(-this->arg);
      outasm(", %esp");
      nl();
    }
  }
  else if(this->code==CD_SHL)
  {
    ol("movl %eax, %ecx");
    ol("movl %edx, %eax");
    ol("sall %cl, %eax");
  }
  else if(this->code==CD_ASR)
  {
    ol("movl %eax, %ecx");
    ol("movl %edx, %eax");
    ol("sarl %cl, %eax");
  }
  else if(this->code==CD_SHR)
  {
    ol("movl %eax, %ecx");
    ol("movl %edx, %eax");
    ol("shrl %cl, %eax");
  }
  else if(this->code==CD_MULREG)
  {
    xmulreg(this->arg,this->reg[regnames]);
  }
  else if(this->code==CD_DIVCONST)
  {
    xdivconst(this->arg);
  }
  else if(this->code==CD_PUSH)
  {
    ol("pushl %eax");
  }
  else if(this->code==CD_POP)
  {
    ol("popl %edx");
  }
  else if(this->code==CD_MOVAD)
  ol("movl %eax, %edx");
  else if(this->code==CD_MOVR)   /* AT&T: src, dst */
  movins("movl ",regnames[this->arg],regnames[this->reg]);
  else if(this->code==CD_RET)
  {
    ol("ret");
  }
  else if(this->code==CD_LDLIT)
  {
    ot("movl $");
    printlab(stlab);
    outstr("+");
    outdec(this->arg);
    outstr(", ");outstr(regnames[this->reg]);
    nl();
  }
  else if(this->code==CD_LDN)
  {
    if(this->arg==0)
    {ot("xorl ");outstr(regnames[this->reg]);outstr(", ");outstr(regnames[this->reg]);nl();}
    else
    {
      ot("movl $");
      outdec(this->arg);
      outstr(", ");outstr(regnames[this->reg]);
      nl();
    }
  }
  else if(this->code==CD_LDA)
  {
    ot("movl $");
    outname(this->str);
    if(this->arg)
    {outasm("+");outdec(this->arg);}
    outasm(", ");outstr(regnames[this->reg]);
    nl();
  }
  else if(this->code==CD_LEA)
  {
    ot("leal ");
    outdec(this->arg);
    outasm("(%ebp), ");outstr(regnames[this->reg]);
    nl();
  }
  else if(this->code==CD_STOW)
  {
    ot("movl %eax, ");
    outname(this->str);
    if(this->arg)
    {outstr("+");outdec(this->arg);}
    nl();
  }
  else if(this->code==CD_STOB)
  {
    ot("movb %al, ");
    outname(this->str);
    if(this->arg)
    {outstr("+");outdec(this->arg);}
    nl();
  }
  else if(this->code==CD_STOB2)
  {
    ot("movb %al, ");
    outdec(this->arg);
    outstr("(%edx)");nl();
  }
  else if(this->code==CD_STOW2)
  {
    ot("movl %eax, ");
    outdec(this->arg);
    outstr("(%edx)");nl();
  }
  else if(this->code==CD_STLW)
  {
    ot("movl %eax, ");
    outdec(this->arg);outasm("(%ebp)");nl();
  }
  else if(this->code==CD_STLB)
  {
    ot("movb %al, ");
    outdec(this->arg);outasm("(%ebp)");nl();
  }
  else if(this->code==CD_LBRB)
  {
    ot("movsbl ");
    outdec(this->arg);
    outstr("(%eax), %eax");nl();
  }
  else if(this->code==CD_LBRW)
  {
    ot("movl ");
    outdec(this->arg);
    outstr("(%eax), %eax");nl();
  }
  else if(this->code==CD_LBRA)
  {
    ot("leal ");
    outdec(this->arg);
    outstr("(%eax), %eax");nl();
  }
  else if(this->code==CD_LDW)
  {
    ot("movl ");
    outname(this->str);
    if(this->arg)
    {
      outasm("+");
      outdec(this->arg);
    }
    outasm(", ");outstr(regnames[this->reg]);nl();
  }
  else if(this->code==CD_LDB)
  {
    ot("movsbl ");
    outname(this->str);
    if(this->arg)
    {
      outasm("+");
      outdec(this->arg);
    }
    outasm(", ");outstr(regnames[this->reg]);nl();
  }
  else if(this->code==CD_LDLW)
  {
    ot("movl ");
    outdec(this->arg);
    outasm("(%ebp), ");outstr(regnames[this->reg]);
    nl();
  }
  else if(this->code==CD_LDLB)
  {
    ot("movsbl ");
    outdec(this->arg);
    outasm("(%ebp), ");outstr(regnames[this->reg]);
    nl();
  }
  /* ---- i386 x87 floating point (M4 slice 6) -----------------------------
     The flat-register FP IR maps onto the x87 register stack with st(0) as the
     accumulator (mirroring %xmm0). Loads push (fld), stores pop (fstp), and
     binary-op operands spill to the integer stack via FPUSH/FPOP, so st depth
     stays <= 2 during evaluation and 0 between statements. After FPOP the stack
     is st0=left, st1=right; the GAS mnemonics faddp/fsubp/fmulp/fdivp then give
     left OP right (verified empirically -- GAS reverses fsub/fdiv vs Intel).
     Scope: scalar arithmetic, conversions, float, arrays/deref, double->int at
     return. The FP *calling convention* (passing/returning doubles across calls)
     is not done here -- see the i386 caller guard in langc.e. */
  else if(this->code==CD_FLDLIT)
  {ot("fldl .LF");outdec(this->arg);nl();}
  else if(this->code==CD_FLDLOC)
  {ot("fldl ");outdec(this->arg);outstr("(%ebp)");nl();}
  else if(this->code==CD_FLDGLB)
  {
    ot("fldl ");outname(this->str);
    if(this->arg){outasm("+");outdec(this->arg);}
    nl();
  }
  else if(this->code==CD_FSTLOC)
  {ot("fstpl ");outdec(this->arg);outstr("(%ebp)");nl();}
  else if(this->code==CD_FSTGLB)
  {
    ot("fstpl ");outname(this->str);
    if(this->arg){outasm("+");outdec(this->arg);}
    nl();
  }
  else if(this->code==CD_FPUSH)
  {ol("subl $8, %esp");ol("fstpl (%esp)");}
  else if(this->code==CD_FPOP)
  {ol("fldl (%esp)");ol("addl $8, %esp");}
  else if(this->code==CD_FADD)
  ol("faddp %st, %st(1)");
  else if(this->code==CD_FSUB)
  ol("fsubp %st, %st(1)");
  else if(this->code==CD_FMUL)
  ol("fmulp %st, %st(1)");
  else if(this->code==CD_FDIV)
  ol("fdivp %st, %st(1)");
  else if(this->code==CD_I2F)
  {ol("pushl %eax");ol("fildl (%esp)");ol("addl $4, %esp");}
  else if(this->code==CD_I2F1)
  {ol("pushl %edx");ol("fildl (%esp)");ol("addl $4, %esp");}
  else if(this->code==CD_F2I)
  {
    /* truncate st0 -> int %eax (round-toward-zero), popping st0. Save the x87
       control word, set RC=11 (chop), fistpl, restore. */
    ol("subl $8, %esp");
    ol("fnstcw (%esp)");
    ol("movzwl (%esp), %eax");
    ol("orb $12, %ah");          /* set rounding-control bits (0x0C00) */
    ol("movw %ax, 2(%esp)");
    ol("fldcw 2(%esp)");
    ol("fistpl 4(%esp)");
    ol("fldcw (%esp)");
    ol("movl 4(%esp), %eax");
    ol("addl $8, %esp");
  }
  else if(this->code==CD_FLDLOCS)   /* 4-byte float: x87 loads/stores it directly */
  {ot("flds ");outdec(this->arg);outstr("(%ebp)");nl();}
  else if(this->code==CD_FLDGLBS)
  {
    ot("flds ");outname(this->str);
    if(this->arg){outasm("+");outdec(this->arg);}
    nl();
  }
  else if(this->code==CD_FSTLOCS)
  {ot("fstps ");outdec(this->arg);outstr("(%ebp)");nl();}
  else if(this->code==CD_FSTGLBS)
  {
    ot("fstps ");outname(this->str);
    if(this->arg){outasm("+");outdec(this->arg);}
    nl();
  }
  else if(this->code==CD_FLBR)      /* deref: address in %eax */
  {ot("fldl ");outdec(this->arg);outstr("(%eax)");nl();}
  else if(this->code==CD_FLBRS)
  {ot("flds ");outdec(this->arg);outstr("(%eax)");nl();}
  else if(this->code==CD_FSTBR2)    /* store through popped address in %edx */
  {ot("fstpl ");outdec(this->arg);outstr("(%edx)");nl();}
  else if(this->code==CD_FSTBR2S)
  {ot("fstps ");outdec(this->arg);outstr("(%edx)");nl();}
  else if((this->code>=CD_MARGINT)&&(this->code<=CD_SARGFP))
  error("FP register marshaling is x86_64-only (no i386 FP calling convention)");
  else if(this->code==CD_IGNORE)
  ;
  else
  {
    fprintf(stderr,"%d ",this->code);
    error("unknown opcode");
  }
}
func xdivconst(k:int)
{
  var int:l;
  if(k==1)return ;
  if(!k){
  error("division by zero");
  return ;
  }
  l=1;
  while(l<15)if(k==(1<<l)){
  ot("sarl $");
  outdec(l);
  outstr(", %eax");
  nl();
  return ;
  }
  else
  l++;
  ol("cltd");
  ot("divl $");
  outdec(k);
  nl();
}
func xmulreg(k:int,s:*char)
{
  var int:l;
  if(k==1)return ;
  else
  if(k==0){
    ot("xorl ");
    outstr(s);
    outstr(", ");
    outstr(s);
    nl();
  }
  else
    {
    l=1;
    while(l<15)if(k==(1<<l)){
      ot("sall $");
      outdec(l);
      outstr(", ");
      outstr(s);
      nl();
      return ;
    }
    else
      l++;
    }
  ot("imull $");
  outdec(k);
  outstr(", ");
  outstr(s);
  nl();
}
func cd_init(*scode:this)
{
  this->code=0;
  this->arg=0;
  this->reg=RG_A;
  this->str=0;
}
func cd_done(this:*scode)
{
  if(this->str)
  free(this->str);
  this->code=0;
  this->arg=0;
  this->reg=RG_A;
  this->str=0;
}
func strdyn(*char:s)
{
  var int :l;
  var *char:res;
  l=strlen(s);
  chkmem(res=calloc(l+1,sizeof(char)));
  strcp(res,s);
  return res;
}
func mulreg(k:int,int s)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_MULREG;
  cd->arg=k;
  cd->reg=s;
}
func increg(k:int)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_INCREG;
  cd->arg=k;
}
func decreg(k:int)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_DECREG;
  cd->arg=k;
}
func mult()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_MUL2REGS;
}
func div()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_DIV2REGS;
}
func zmod()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_MOD2REGS;
}
func zpop()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_POP;
  Zsp=Zsp+target.stackslot;   /* ==wordsize except arm64 (16) */
}
func zpush()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_PUSH;
  Zsp=Zsp-target.stackslot;
}
func zret()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_RET;
}
func divconst(int k)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_DIVCONST;
  cd->arg=k;
}
func zadd()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_ADD2REGS;
}
func zsub()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_SUB2REGS;
}
func neg()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_NEG;
}
func zeq()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_EQ;
}
func zne()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_NEQ;
}
func zge()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_ZGE;
}
func uge()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_UGE;
}
func ule()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_ULE;
}
func zle()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_ZLE;
}
func ult()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_ULT;
}
func zlt()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_ZLT;
}
func ugt()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_UGT;
}
func zgt()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_ZGT;
}
func zor()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_BOR2REGS;
}
func zxor()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_BXOR2REGS;
}
func zand()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_BAND2REGS;
}
func asr()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_ASR;
}
func asl()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_SHL;
}
func lnot()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_LNOT;
}
func bnot()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_BNOT;
}
func testjump(label:int)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_TESTJUMP;
  cd->arg=label;
}
func testnejump(label:int)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_TESTNEJUMP;
  cd->arg=label;
}
func jump(label:int)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_JUMP;
  cd->arg=label;
}
func zcall(sname:*char,alval:int)   /* alval = #vector regs for %al (SysV varargs) */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_ZCALL;
  cd->str=strdyn(sname);
  cd->arg=alval;
}
func margint(slot:int,reg:int)   /* M4: load int arg from stack into arg register */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_MARGINT;
  cd->arg=slot;
  cd->reg=reg;
}
func margfp(slot:int,reg:int)    /* M4: load double arg from stack into %xmm<reg> */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_MARGFP;
  cd->arg=slot;
  cd->reg=reg;
}
func sargint(slot:int,reg:int)   /* M4: spill an int arg register to a param slot */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_SARGINT;
  cd->arg=slot;
  cd->reg=reg;
}
func sargfp(slot:int,reg:int)    /* M4: spill %xmm<reg> to a double param slot */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_SARGFP;
  cd->arg=slot;
  cd->reg=reg;
}
func spillargs(n:int)   /* x86_64 SysV: spill n arg registers to param slots */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_SPILLARGS;
  cd->arg=n;
}
func marshal(n:int)     /* x86_64 SysV: load n pushed args into arg registers */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_MARSHAL;
  cd->arg=n;
}
func cloadflit(idx:int) /* M4: load float literal .LF<idx> into the FP accum */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_FLDLIT;
  cd->arg=idx;
}
func zf2i()             /* M4: convert FP accumulator to int accumulator */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_F2I;
}
func cfldloc(offset:int)   /* M4: load local double */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_FLDLOC;
  cd->arg=offset;
}
func cfldglb(name:*char,offset:int)   /* M4: load global double */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_FLDGLB;
  cd->str=strdyn(name);
  cd->arg=offset;
}
func cfstloc(offset:int)   /* M4: store to local double */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_FSTLOC;
  cd->arg=offset;
}
func cfstglb(name:*char,offset:int)   /* M4: store to global double */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_FSTGLB;
  cd->str=strdyn(name);
  cd->arg=offset;
}
func cfldlocs(offset:int)   /* M4 slice 5: load local float (widen to double) */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_FLDLOCS;
  cd->arg=offset;
}
func cfldglbs(name:*char,offset:int)   /* M4 slice 5: load global float */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_FLDGLBS;
  cd->str=strdyn(name);
  cd->arg=offset;
}
func cfstlocs(offset:int)   /* M4 slice 5: narrow & store to local float */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_FSTLOCS;
  cd->arg=offset;
}
func cfstglbs(name:*char,offset:int)   /* M4 slice 5: narrow & store to global float */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_FSTGLBS;
  cd->str=strdyn(name);
  cd->arg=offset;
}
func cfldbre(offset:int)   /* M4: load double through the pointer in %rax */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_FLBR;
  cd->arg=offset;
}
func cfldbres(offset:int)  /* M4: load float through %rax, widen to double */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_FLBRS;
  cd->arg=offset;
}
func cfstbre2(offset:int)  /* M4: store double through the popped address in %rdx */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_FSTBR2;
  cd->arg=offset;
}
func cfstbre2s(offset:int) /* M4: narrow & store float through %rdx */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_FSTBR2S;
  cd->arg=offset;
}
func fpslot()   /* bytes a pushed double occupies: 8, but 16 on arm64 (align) */
{
  var int:s;
  s=target.stackslot;
  if(s<8)s=8;   /* i386: a double is 8 bytes even though the word is 4 */
  return s;
}
func fpush()            /* M4: push the FP accumulator */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_FPUSH;
  Zsp=Zsp-fpslot();
}
func fpop()             /* M4: pop into the 2nd FP register */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_FPOP;
  Zsp=Zsp+fpslot();
}
func fbinop(op:int)     /* M4: emit one FP arithmetic opcode */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=op;
}
func i2f()              /* M4: promote int accumulator -> FP accumulator */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_I2F;
}
func i2f1()             /* M4: promote %rdx (popped left int) -> %xmm1 */
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_I2F1;
}
func cmodstk(k:int)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_MODSTK;
  cd->arg=k;
}
func zenter()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_STKENTER;
}
func zleave()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_STKLEAVE;
}
func clab(int label)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_LAB;
  cd->arg=label;
}
func cloadlita(offs:int)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_LDLIT;
  cd->arg=offs;
}
func zldn(k:int)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_LDN;
  cd->arg=k;
}
func zlda(*char:name,int offset)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_LDA;
  cd->str=strdyn(name);
  cd->arg=offset;
}
func zlea(offset:int)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_LEA;
  cd->arg=offset;
}
func zstow(*char:name,offset:int)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_STOW;
  cd->str=strdyn(name);
  cd->arg=offset;
}
func zstob(*char:name,offset:int)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_STOB;
  cd->str=strdyn(name);
  cd->arg=offset;
}
func zstlw(int offset)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_STLW;
  cd->arg=offset;
}
func zstlb(int offset)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_STLB;
  cd->arg=offset;
}
func zlbrw(offset:int)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_LBRW;
  cd->arg=offset;
}
func zlbrb(offset:int)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_LBRB;
  cd->arg=offset;
}
func zlbra(offset:int)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_LBRA;
  cd->arg=offset;
}
func zldw(*char:name,int offset)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_LDW;
  cd->str=strdyn(name);
  cd->arg=offset;
}
func zldb(*char:name,int offset)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_LDB;
  cd->str=strdyn(name);
  cd->arg=offset;
}
func zldlw(int offset)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_LDLW;
  cd->arg=offset;
}
func zldlb(int offset)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_LDLB;
  cd->arg=offset;
}
func zstow2(int offset)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_STOW2;
  cd->arg=offset;
}
func zstob2(int offset)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_STOB2;
  cd->arg=offset;
}

func tstcg()
{
  var scodegen:cg;
  cg_init(&cg);
  var *scode:cd;
  cd=cg_getitem(&cg);
  cd->code=CD_LAB;
  cd->arg=19;
  cd=cg_getitem(&cg);
  cd->code=CD_ZCALL;
  cd->str=strdyn("function2");
  cd=cg_getitem(&cg);
  cd->code=CD_TESTJUMP;
  cd->arg=19;
  cd=cg_getitem(&cg);
  cd->code=CD_TESTNEJUMP;
  cd->arg=20;
  cg_print(&cg);
  cg_done(&cg);
}
var **char:regnames;
var *scodegen:ccg;
var scodegen:cgglb;
func icodegen()
{
  /*fprintf(stderr,"icodegen()\n");*/
  chkmem(regnames=calloc(4,sizeof(*char)));
  if(target.arch==ARCH_ARM64)
  {
    /* x0 = accumulator (RG_A), x1 = 2nd operand (RG_D), x2/x3 = scratch */
    regnames[RG_A]="x0";
    regnames[RG_B]="x2";
    regnames[RG_C]="x3";
    regnames[RG_D]="x1";
  }
  else if(target.arch==ARCH_RISCV)
  {
    /* a0 = accumulator (RG_A), a1 = 2nd operand (RG_D), t0 = address scratch
       (the helpers hardcode t0); t1/t2 = the regspill saves (RG_B/RG_C), kept
       clear of t0 so a held save survives an address computation in its span. */
    regnames[RG_A]="a0";
    regnames[RG_B]="t1";
    regnames[RG_C]="t2";
    regnames[RG_D]="a1";
  }
  else if(target.arch==ARCH_MIPS)
  {
    /* $2 = accumulator (RG_A), $3 = 2nd operand (RG_D), $12/$13 = address+imm
       scratch (the helpers hardcode them); $14/$15 = the regspill saves
       (RG_B/RG_C), kept clear of $12/$13 so a held save survives an address
       computation in its span. N64 args go in $4..$11, clear of all these. */
    regnames[RG_A]="$2";
    regnames[RG_B]="$14";
    regnames[RG_C]="$15";
    regnames[RG_D]="$3";
  }
  else if(target.arch==ARCH_X86_64)
  {
    regnames[RG_A]="%rax";
    regnames[RG_B]="%rbx";
    /* RG_C is a regspill save register, so it must survive every operation in
       its (call-free) span. %rcx is clobbered by shifts (need %cl) and div/mod
       (used as the divisor temp), so use %r12 -- callee-saved and otherwise
       unused by the backend. RG_C is never used by an op lowering (those keep
       hardcoding %rcx), only by regspill, so this is a pure relocation. */
    regnames[RG_C]="%r12";
    regnames[RG_D]="%rdx";
  }
  else
  {
    regnames[RG_A]="%eax";
    regnames[RG_B]="%ebx";
    regnames[RG_C]="%esi";  /* not %ecx: shifts/div clobber it (see x86_64) */
    regnames[RG_D]="%edx";
  }
  ccg=&cgglb;
  cg_init(ccg);
  /*fprintf(stderr,"ccg=%d\n",ccg);*/
}
func dcodegen()
{
  /*fprintf(stderr,"dcodegen()\n");*/
  /*fprintf(stderr,"ccg=%d\n",ccg);*/
  /*fprintf(stderr,"ccg.codeptr=%d\n",ccg->codeptr);*/
  cg_print(ccg);
  cg_done(ccg);
  if(regnames)
  free(regnames);
}

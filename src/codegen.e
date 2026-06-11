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
func cg_print(*scodegen this)
{
  var int:i;
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
  else cd_write_i386(this);
}
/* x86_64 (System V) instruction lowering. Mirrors cd_write_i386 with 64-bit
   registers and `q` suffixes; UPLNC's word is 8 bytes here (int==pointer).
   The calling convention (CD_ZCALL) is M2 Phase 2b-iii -- this covers call-free
   integer/pointer programs. */
func cd_write_x86_64(*scode:this)
{
  if(this->code==CD_ZCALL)
  {
    /* UPLNC<->UPLNC calls use the stack convention (args pushed; callee reads
       them at 2*wordsize(%rbp)+). libc calls (SysV register args + 16-byte
       alignment) are M2 Phase 2b-iii-b. */
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
    outstr(", %rax");
    nl();
  }
  else if(this->code==CD_LDN)
  {
    if(this->arg==0)
    ol("xorq %rax, %rax");
    else
    {
      ot("movq $");
      outdec(this->arg);
      outstr(", %rax");
      nl();
    }
  }
  else if(this->code==CD_LDA)
  {
    ot("movq $");
    outname(this->str);
    if(this->arg)
    {outasm("+");outdec(this->arg);}
    outasm(", %rax");
    nl();
  }
  else if(this->code==CD_LEA)
  {
    ot("leaq ");
    outdec(this->arg);
    outasm("(%rbp), %rax");
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
    outasm(", %rax");nl();
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
    outasm(", %rax");nl();
  }
  else if(this->code==CD_LDLW)
  {
    ot("movq ");
    outdec(this->arg);
    outasm("(%rbp), %rax");
    nl();
  }
  else if(this->code==CD_LDLB)
  {
    ot("movsbq ");
    outdec(this->arg);
    outasm("(%rbp), %rax");
    nl();
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
    outstr(", %eax");
    nl();
  }
  else if(this->code==CD_LDN)
  {
    if(this->arg==0)
    ol("xorl %eax, %eax");
    else
    {
      ot("movl $");
      outdec(this->arg);
      outstr(", %eax");
      nl();
    }
  }
  else if(this->code==CD_LDA)
  {
    ot("movl $");
    outname(this->str);
    if(this->arg)
    {outasm("+");outdec(this->arg);}
    outasm(", %eax");
    nl();
  }
  else if(this->code==CD_LEA)
  {
    ot("leal ");
    outdec(this->arg);
    outasm("(%ebp), %eax");
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
    outasm(", %eax");nl();
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
    outasm(", %eax");nl();
  }
  else if(this->code==CD_LDLW)
  {
    ot("movl ");
    outdec(this->arg);
    outasm("(%ebp), %eax");
    nl();
  }
  else if(this->code==CD_LDLB)
  {
    ot("movsbl ");
    outdec(this->arg);
    outasm("(%ebp), %eax");
    nl();
  }
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
  Zsp=Zsp+target.wordsize;
}
func zpush()
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_PUSH;
  Zsp=Zsp-target.wordsize;
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
func zcall(sname:*char)
{
  var *scode:cd;
  cd=cg_getitem(ccg);
  cd->code=CD_ZCALL;
  cd->str=strdyn(sname);
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
  if(target.arch==ARCH_X86_64)
  {
    regnames[RG_A]="%rax";
    regnames[RG_B]="%rbx";
    regnames[RG_C]="%rcx";
    regnames[RG_D]="%rdx";
  }
  else
  {
    regnames[RG_A]="%eax";
    regnames[RG_B]="%ebx";
    regnames[RG_C]="%ecx";
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

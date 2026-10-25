#!/usr/bin/env python3
"""Exercise the owned Windows reader with host threads and deterministic WinAPI mocks."""

import argparse
import importlib.util
import json
import re
import subprocess
from pathlib import Path


HARNESS = r'''
#define _DEFAULT_SOURCE 1
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sched.h>
typedef uint64_t U;
typedef uint32_t D;
extern U __axiom_win_reader_ready(U), __axiom_win_reader_read(U,U,U);
extern U __axiom_win_reader_mode(U,U), __axiom_win_reader_close(U);
extern U __axiom_win_poller_alive(U), __axiom_win_poller_retire(U);
#define SIGNED(x) ((int64_t)(x))
#define CHECK(c, label) do { if (!(c)) { fprintf(stderr, "FAIL %s\n", label); exit(1); } } while (0)
enum { MAX_STREAMS=80, MAX_THREADS=240, MAX_ALLOCS=100, QSIZE=12 };
enum { WAITING=0, PREPARING=1, READING=2, FINISHED=3 };
struct Action { D count, error; unsigned char bytes[128]; };
struct Stream {
    U handle; int kind, closed, close_calls, read_calls, mode_calls, cancel_calls;
    int pre_gate, hold_completion, mode_gate, mode_entered, mode_active;
    int fail_mode, close_error, fail_wait, fail_cancel, non_console, head, tail;
    int abandoned_read, emulate_conhost_cancel, fail_open, private_close_error, console_output;
    U last_mode, largest_read;
    struct Action queue[QSIZE];
};
struct Thread {
    pthread_t id; U handle, entry, argument; int phase, cancelled, closed;
};
struct InputHandle { U handle, source; int closed, abandoned_read; };
struct Alloc { void *raw, *memory; U size; int freed; };
static pthread_mutex_t mu=PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed=PTHREAD_COND_INITIALIZER;
static struct Stream streams[MAX_STREAMS];
static struct Thread *threads[MAX_THREADS];
static struct InputHandle inputs[MAX_THREADS];
static struct Alloc allocations[MAX_ALLOCS];
static int nstreams, nthreads, ninputs, nallocs, fail_create, fail_alloc;
static int bad_buffer, bad_free, mode_read_overlap;
static _Thread_local U last_error;
static _Thread_local struct Thread *current;
static _Thread_local U console_source;
static void lock(void) { pthread_mutex_lock(&mu); }
static void unlock(void) { pthread_mutex_unlock(&mu); }
static struct InputHandle *input(U h) {
    for(int i=0;i<ninputs;i++)if(inputs[i].handle==h)return &inputs[i];
    return 0;
}
static struct Stream *stream(U h) {
    struct InputHandle *in=input(h); if(in)h=in->source;
    for(int i=0;i<nstreams;i++) if(streams[i].handle==h) return &streams[i];
    abort();
}
static U fresh(int kind) {
    lock(); CHECK(nstreams<MAX_STREAMS,"stream capacity");
    struct Stream *s=&streams[nstreams++]; s->handle=(U)nstreams+100; s->kind=kind;
    U h=s->handle; unlock(); return h;
}
static void reuse(U h,int kind) {
    lock();struct Stream *s=stream(h);CHECK(s->closed,"only a closed HANDLE is recycled");
    memset(s,0,sizeof(*s));s->handle=h;s->kind=kind;unlock();
}
static void queue(U h, const char *bytes, D error) {
    lock(); struct Stream *s=stream(h); CHECK(s->tail<QSIZE,"action capacity");
    /* Conhost can retain a server read after client cancellation. The next
       input is consumed until its independently opened input handle closes.
       See microsoft/terminal issues 12143 and 17791; native CI probes this. */
    if(s->emulate_conhost_cancel) {
        if(s->abandoned_read) { s->abandoned_read=0; unlock(); return; }
        for(int i=0;i<ninputs;i++)if(inputs[i].source==h && !inputs[i].closed && inputs[i].abandoned_read) {
            inputs[i].abandoned_read=0; unlock(); return;
        }
    }
    struct Action *a=&s->queue[s->tail++]; a->error=error;
    if(bytes) { a->count=(D)strlen(bytes); memcpy(a->bytes,bytes,a->count); }
    pthread_cond_broadcast(&changed); unlock();
}
static int stat(U h,int which) {
    lock(); struct Stream *s=stream(h); int v=0;
    if(which==0)v=s->read_calls;
    if(which==1)v=s->cancel_calls;
    if(which==2)v=s->close_calls;
    if(which==3)v=s->mode_entered;
    unlock(); return v;
}
static int live_allocations(void) {
    lock();int live=0;for(int i=0;i<nallocs;i++)live+=!allocations[i].freed;unlock();return live;
}
static void await_stat(U h,int which,int minimum) {
    for(int i=0;i<2000;i++) { if(stat(h,which)>=minimum)return; usleep(1000); }
    CHECK(0,"mock operation did not arrive");
}
static int await_ready(U h) {
    for(int i=0;i<2000;i++) {
        U r=__axiom_win_reader_ready(h); if(r)return (int)SIGNED(r); usleep(1000);
    }
    CHECK(0,"reader did not become ready"); return -1;
}
U GetLastError(void) { return last_error|0x123400000000ULL; }
U GetFileType(U h) { lock(); int k=stream(h)->kind; unlock(); return (U)k|0x123400000000ULL; }
U GetConsoleMode(U h,U destination) {
    lock();struct Stream *s=stream(h);int console=s->kind==2 && !s->non_console;
    if(console)*(D*)(uintptr_t)destination=7;else last_error=6;
    unlock();return console?0x123400000001ULL:0x123400000000ULL;
}
U GetNumberOfConsoleInputEvents(U h,U destination) {
    lock();struct Stream *s=stream(h);int readable=s->kind==2 && !s->non_console && !s->console_output;
    if(readable) { *(D*)(uintptr_t)destination=0;console_source=h; } else last_error=6;
    unlock();return readable?0x123400000001ULL:0x123400000000ULL;
}
U CreateFileW(U name,U access,U share,U security,U disposition,U flags,U template) {
    static const uint16_t expected[]={'C','O','N','I','N','$',0};
    CHECK(!memcmp((void*)(uintptr_t)name,expected,sizeof(expected)),"worker opens console input");
    CHECK(access==0x80000000ULL && share==3 && !security && disposition==3 && !flags && !template,
          "private console reader is read-only, shared and non-inheritable");
    lock();struct Stream *s=stream(console_source);
    if(s->fail_open) { s->fail_open=0;last_error=5;unlock();return ~(U)0; }
    CHECK(ninputs<MAX_THREADS,"private input capacity");
    struct InputHandle *in=&inputs[ninputs++];in->handle=10000+ninputs;in->source=console_source;
    U h=in->handle;unlock();return h;
}
U Sleep(U ms) { if(ms)usleep((useconds_t)(ms*1000)); else sched_yield(); return 0; }
U VirtualAlloc(U address,U size,U type,U protect) {
    (void)address; CHECK(type==12288 && protect==4,"VirtualAlloc flags");
    lock();
    if(fail_alloc) { fail_alloc=0; last_error=8; unlock(); return 0; }
    CHECK(nallocs<MAX_ALLOCS,"allocation capacity");
    struct Alloc *a=&allocations[nallocs++]; a->raw=malloc((size_t)size+64);
    CHECK(a->raw!=0,"host allocation"); memset(a->raw,0xA5,(size_t)size+64);
    a->memory=(unsigned char*)a->raw+32; a->size=size; memset(a->memory,0,(size_t)size);
    U result=(U)(uintptr_t)a->memory; unlock(); return result;
}
U VirtualFree(U address,U size,U type) {
    CHECK(!size && type==32768,"VirtualFree flags"); lock();
    struct Alloc *a=0; for(int i=0;i<nallocs;i++) if((U)(uintptr_t)allocations[i].memory==address)a=&allocations[i];
    CHECK(a && !a->freed,"state freed once");
    for(int i=0;i<nthreads;i++) if(threads[i]->argument==address && threads[i]->phase!=FINISHED)bad_free=1;
    for(int i=0;i<32;i++) if(((unsigned char*)a->raw)[i]!=0xA5 || ((unsigned char*)a->memory)[a->size+i]!=0xA5)bad_free=1;
    a->freed=1; free(a->raw); pthread_cond_broadcast(&changed); unlock(); return 1;
}
static void *thread_start(void *p) {
    struct Thread *t=p; current=t;
    D (*entry)(void*)=(void*)(uintptr_t)t->entry; entry((void*)(uintptr_t)t->argument);
    lock(); t->phase=FINISHED; pthread_cond_broadcast(&changed); unlock(); return 0;
}
U CreateThread(U security,U stack,U entry,U argument,U flags,U out) {
    CHECK(!security && !stack && !flags && !out,"CreateThread flags"); lock();
    if(fail_create) { fail_create=0; last_error=8; unlock(); return 0; }
    CHECK(nthreads<MAX_THREADS,"thread capacity");
    struct Thread *t=calloc(1,sizeof(*t)); CHECK(t,"thread allocation");
    t->handle=(U)(uintptr_t)t; t->entry=entry; t->argument=argument; threads[nthreads++]=t;
    CHECK(!pthread_create(&t->id,0,thread_start,t),"native thread create");
    unlock(); return t->handle;
}
static struct Thread *thread(U handle) {
    for(int i=0;i<nthreads;i++) if(threads[i]->handle==handle)return threads[i];
    return 0;
}
U test_thread_stream[MAX_THREADS];
static struct Stream *thread_stream(struct Thread *t) {
    for(int i=0;i<nthreads;i++) if(threads[i]==t && test_thread_stream[i])return stream(test_thread_stream[i]);
    return 0;
}
U WaitForSingleObject(U handle,U timeout) {
    CHECK(timeout==0,"join polls without an uninterruptible wait"); lock();
    struct Thread *t=thread(handle); CHECK(t && !t->closed,"wait on live thread handle");
    struct Stream *s=thread_stream(t);
    if(s && s->fail_wait) { s->fail_wait=0;last_error=5;unlock();return 0x1234FFFFFFFFULL; }
    U result=t->phase==FINISHED?0:258; unlock(); return result|0x123400000000ULL;
}
U CloseHandle(U handle) {
    lock(); struct Thread *t=thread(handle);
    if(t) { CHECK(!t->closed,"thread handle closed once"); t->closed=1; unlock(); return 0x123400000001ULL; }
    struct InputHandle *in=input(handle);
    if(in) {
        CHECK(!in->closed,"private input handle closed once");
        for(int i=0;i<nthreads;i++)if(test_thread_stream[i]==handle)
            CHECK(threads[i]->phase!=PREPARING && threads[i]->phase!=READING,
                  "private input closes only after synchronous read completion");
        if(stream(in->source)->private_close_error) {
            last_error=stream(in->source)->private_close_error;unlock();return 0x123400000000ULL;
        }
        in->closed=1;in->abandoned_read=0;unlock();return 0x123400000001ULL;
    }
    struct Stream *s=stream(handle); s->close_calls++;
    if(s->closed || s->close_error) { last_error=s->close_error?s->close_error:6; unlock(); return 0x123400000000ULL; }
    s->closed=1; unlock(); return 0x123400000001ULL;
}
U CancelSynchronousIo(U handle) {
    lock(); struct Thread *t=thread(handle); CHECK(t && !t->closed,"cancel live thread");
    struct Stream *s=thread_stream(t);
    if(s)s->cancel_calls++;
    if(s && s->fail_cancel) { s->fail_cancel=0;last_error=5;unlock();return 0x123400000000ULL; }
    U result=0;
    if(t->phase==READING) { t->cancelled=1; result=1; } else last_error=1168;
    pthread_cond_broadcast(&changed); unlock(); return result|0x123400000000ULL;
}
U test_no_cancel(U handle) { (void)handle; last_error=1168; return 0; }
U ReadFile(U handle,U destination,U count,U written,U overlapped) {
    CHECK(!overlapped && count<=4294967295ULL,"ReadFile synchronous DWORD count");
    lock(); struct Stream *s=stream(handle); s->read_calls++; if(count>s->largest_read)s->largest_read=count;
    struct InputHandle *in=input(handle);CHECK(!in || !in->closed,"read uses a live private input");
    if(s->mode_active)mode_read_overlap=1;
    if(current) {
        int owned=0;
        for(int i=0;i<nallocs;i++) {
            U base=(U)(uintptr_t)allocations[i].memory;
            if(!allocations[i].freed && destination>=base && destination+count<=base+allocations[i].size)owned=1;
        }
        if(!owned)bad_buffer=1;
        for(int i=0;i<nthreads;i++) if(threads[i]==current)test_thread_stream[i]=handle;
        current->phase=PREPARING;
        pthread_cond_broadcast(&changed);
        while(s->pre_gate)pthread_cond_wait(&changed,&mu);
        current->phase=READING;
    }
    pthread_cond_broadcast(&changed);
    while((s->head==s->tail || (s->hold_completion && !s->cancel_calls)) && !(current && current->cancelled))
        pthread_cond_wait(&changed,&mu);
    D got=0; U result=0;
    /* Completion can win a simultaneous cancellation. */
    if(s->head<s->tail) {
        struct Action *a=&s->queue[s->head++]; got=a->count;
        if(got>count)got=(D)count;
        if(got)memcpy((void*)(uintptr_t)destination,a->bytes,got);
        last_error=a->error; result=a->error?0:1;
    } else {
        last_error=995;
        if(s->emulate_conhost_cancel && s->kind==2) {
            if(in)in->abandoned_read=1;else s->abandoned_read=1;
        }
    }
    *(D*)(uintptr_t)written=got;
    if(current) { current->cancelled=0; current->phase=WAITING; }
    pthread_cond_broadcast(&changed); unlock(); return result?0x123400000001ULL:0x123400000000ULL;
}
U SetConsoleMode(U handle,U mode) {
    lock(); struct Stream *s=stream(handle); s->mode_calls++; s->last_mode=mode;
    s->mode_entered=1; s->mode_active=1; pthread_cond_broadcast(&changed);
    while(s->mode_gate)pthread_cond_wait(&changed,&mu);
    s->mode_active=0; U result=s->fail_mode?0:1; if(!result)last_error=5;
    unlock(); return result?0x123400000001ULL:0x123400000000ULL;
}
struct Call { U handle, mode, result; int operation; unsigned char bytes[32]; };
static void *call_runtime(void *p) {
    struct Call *c=p;
    if(c->operation==0)c->result=__axiom_win_reader_close(c->handle);
    if(c->operation==1)c->result=__axiom_win_reader_mode(c->handle,c->mode);
    if(c->operation==2)c->result=__axiom_win_reader_read(c->handle,(U)(uintptr_t)c->bytes,1);
    if(c->operation==3)c->result=__axiom_win_reader_ready(c->handle);
    return 0;
}
static pthread_t launch(struct Call *c) { pthread_t t; CHECK(!pthread_create(&t,0,call_runtime,c),"launch operation");return t; }
static void join_call(pthread_t t) { CHECK(!pthread_join(t,0),"join operation"); }
static void close_ok(U h) { CHECK(__axiom_win_reader_close(h)==0,"close succeeds"); }
static void watchdog(int signal) { (void)signal; const char message[]="watchdog: pending reader did not finish\n"; write(2,message,sizeof(message)-1);_exit(99); }
static void cancellation_only(void) {
    U h=fresh(2); CHECK(__axiom_win_reader_ready(h)==0,"async initial ready"); await_stat(h,0,1); close_ok(h);
}
static _Alignas(8) U lifetime_marker;
static int lifetime_payload;
static void *publish_lifetime(void *ignored) {
    (void)ignored;lifetime_payload=42;__axiom_win_poller_retire((U)(uintptr_t)&lifetime_marker);return 0;
}
static void lifetime(void) {
    for(int i=0;i<256;i++) {
        lifetime_marker=1;lifetime_payload=0;
        CHECK(__axiom_win_poller_alive((U)(uintptr_t)&lifetime_marker)==1,"published poller marker starts alive");
        pthread_t writer;CHECK(!pthread_create(&writer,0,publish_lifetime,0),"marker publisher create");
        while(__axiom_win_poller_alive((U)(uintptr_t)&lifetime_marker))sched_yield();
        CHECK(lifetime_payload==42,"retired marker publishes preceding payload");
        CHECK(!pthread_join(writer,0),"marker publisher join");
        CHECK(__axiom_win_poller_retire((U)(uintptr_t)&lifetime_marker)==0 && __axiom_win_poller_alive((U)(uintptr_t)&lifetime_marker)==0,"retirement is idempotent");
    }
}
int main(int argc,char **argv) {
    (void)argv; signal(SIGALRM,watchdog); alarm(argc>1?2:15);
    if(argc>1) { cancellation_only(); return 0; }
    unsigned char out[32]={0};
    CHECK(__axiom_win_reader_read(999,(U)(uintptr_t)out,0)==0,"zero count has no side effects");
    CHECK(SIGNED(__axiom_win_reader_read(999,(U)(uintptr_t)out,~(U)0))==-87,"negative count is rejected");
    U h=fresh(2);
    CHECK(__axiom_win_reader_ready(h)==0,"initial ready starts asynchronously"); await_stat(h,0,1);
    for(int i=0;i<20;i++)CHECK(__axiom_win_reader_ready(h)==0,"pending reads survive polls");
    CHECK(stat(h,0)==1 && stat(h,1)==0,"polling does not restart or cancel a pending read");
    queue(h,"abcdef",0); CHECK(await_ready(h)==1,"buffered bytes become ready");
    CHECK(__axiom_win_reader_read(h,(U)(uintptr_t)out,2)==2 && !memcmp(out,"ab",2),"first partial bytes");
    CHECK(__axiom_win_reader_ready(h)==1,"partial byte remainder is immediately ready");
    CHECK(__axiom_win_reader_read(h,(U)(uintptr_t)out,3)==3 && !memcmp(out,"cde",3),"second partial bytes");
    CHECK(__axiom_win_reader_ready(h)==1,"last byte remains ready");
    CHECK(__axiom_win_reader_read(h,(U)(uintptr_t)out,32)==1 && out[0]=='f',"last partial byte"); close_ok(h);

    U other=fresh(2);h=fresh(2);
    CHECK(__axiom_win_reader_ready(h)==0 && __axiom_win_reader_ready(other)==0,"two handles start independent workers");
    await_stat(h,0,1);await_stat(other,0,1);queue(h,"one",0);queue(other,"two",0);
    CHECK(await_ready(h)==1 && await_ready(other)==1,"two buffers publish independently");
    CHECK(__axiom_win_reader_read(h,(U)(uintptr_t)out,1)==1 && out[0]=='o',"first handle starts its own buffer");
    CHECK(__axiom_win_reader_mode(h,31)==0,"one handle mode pause");close_ok(h);
    CHECK(__axiom_win_reader_read(other,(U)(uintptr_t)out,3)==3 && !memcmp(out,"two",3),"closing another handle preserves this buffer");
    CHECK(stat(other,1)==0,"unrelated handle was never cancelled");close_ok(other);

    h=fresh(2);queue(h,"abcdef",0);CHECK(await_ready(h)==1,"concurrent consumers have bytes");
    struct Call consumers[6];pthread_t consumer_threads[6];
    for(int i=0;i<6;i++) { consumers[i]=(struct Call){.handle=h,.operation=2};consumer_threads[i]=launch(&consumers[i]); }
    unsigned seen=0;
    for(int i=0;i<6;i++) { join_call(consumer_threads[i]);CHECK(consumers[i].result==1,"each consumer gets one byte");CHECK(consumers[i].bytes[0]>='a' && consumers[i].bytes[0]<='f',"consumer byte is in the buffer");seen|=1U<<(consumers[i].bytes[0]-'a'); }
    CHECK(seen==63,"concurrent consumers take distinct bytes");close_ok(h);

    h=fresh(2);queue(h,"OLD",0);CHECK(await_ready(h)==1,"cached HANDLE before recycling");
    CHECK(__axiom_win_reader_read(h,(U)(uintptr_t)out,1)==1 && out[0]=='O',"consume cached prefix");close_ok(h);
    reuse(h,2);queue(h,"NEW",0);CHECK(__axiom_win_reader_ready(h)==0,"recycled HANDLE starts a fresh worker");
    CHECK(await_ready(h)==1 && __axiom_win_reader_read(h,(U)(uintptr_t)out,3)==3 && !memcmp(out,"NEW",3),"recycled HANDLE drops old cached bytes");close_ok(h);
    h=fresh(3);queue(h,0,109);CHECK(await_ready(h)==1 && __axiom_win_reader_read(h,(U)(uintptr_t)out,1)==0,"EOF HANDLE before recycling");close_ok(h);
    reuse(h,3);queue(h,"new",0);CHECK(__axiom_win_reader_ready(h)==0,"recycled EOF HANDLE starts a fresh worker");
    CHECK(await_ready(h)==1 && __axiom_win_reader_read(h,(U)(uintptr_t)out,3)==3 && !memcmp(out,"new",3),"recycled HANDLE drops old EOF");close_ok(h);

    h=fresh(2); queue(h,0,0); queue(h,0,995); queue(h,"Q",0);
    CHECK(__axiom_win_reader_read(h,(U)(uintptr_t)out,1)==1 && out[0]=='Q',"console zero and interruption retry");
    CHECK(stat(h,0)==3,"console retry keeps the same worker"); close_ok(h);
    for(int i=0;i<3;i++) {
        h=fresh(3); queue(h,0,i==0?109:i==1?232:0);
        CHECK(await_ready(h)==1,"pipe EOF is readable");
        CHECK(__axiom_win_reader_read(h,(U)(uintptr_t)out,1)==0,"pipe EOF returns zero");
        CHECK(__axiom_win_reader_ready(h)==1 && stat(h,0)==1,"EOF remains ready without another read");close_ok(h);
    }
    h=fresh(3); queue(h,0,5); CHECK(await_ready(h)==1,"read error is ready");
    CHECK(SIGNED(__axiom_win_reader_read(h,(U)(uintptr_t)out,1))==-5,"read error preserves low DWORD");close_ok(h);

    h=fresh(2); lock();fail_create=1;unlock();
    CHECK(__axiom_win_reader_ready(h)==1,"thread creation failure is ready");
    CHECK(SIGNED(__axiom_win_reader_read(h,(U)(uintptr_t)out,1))==-8,"thread creation error is returned");close_ok(h);
    h=fresh(2);lock();fail_alloc=1;unlock();
    CHECK(SIGNED(__axiom_win_reader_ready(h))==-8,"native allocation error is returned");
    CHECK(__axiom_win_reader_ready(h)==0,"allocation failure can retry");await_stat(h,0,1);close_ok(h);
    h=fresh(1);CHECK(SIGNED(__axiom_win_reader_ready(h))==-87,"non-stream ready is rejected");
    queue(h,"disk",0);CHECK(__axiom_win_reader_read(h,(U)(uintptr_t)out,4294967296ULL)==4 && !memcmp(out,"disk",4),"direct file read caps DWORD");
    lock();CHECK(stream(h)->largest_read==4294967295ULL,"direct count capped before WinAPI");unlock();close_ok(h);
    h=fresh(2);lock();stream(h)->non_console=1;int old_threads=nthreads;unlock();
    CHECK(SIGNED(__axiom_win_reader_ready(h))==-87,"non-console character device is not console-ready");
    queue(h,0,0);CHECK(__axiom_win_reader_read(h,(U)(uintptr_t)out,1)==0,"serial-style zero-byte read stays a direct successful read");
    lock();CHECK(nthreads==old_threads,"character device never starts a console worker");unlock();
    CHECK(live_allocations()==0,"character device has no console reader state");close_ok(h);

    /* A completion already in flight survives cancellation for a mode change. */
    h=fresh(2);lock();stream(h)->hold_completion=1;unlock();queue(h,"mode",0);
    CHECK(__axiom_win_reader_ready(h)==0,"mode race starts pending read");await_stat(h,0,1);
    CHECK(__axiom_win_reader_mode(h,37)==0,"mode change cancels and joins worker");
    CHECK(__axiom_win_reader_ready(h)==1,"completion survives mode pause");
    CHECK(__axiom_win_reader_read(h,(U)(uintptr_t)out,2)==2 && !memcmp(out,"mo",2),"mode preserves first bytes");
    lock();stream(h)->fail_mode=1;unlock();
    CHECK(SIGNED(__axiom_win_reader_mode(h,38))==-5,"mode BOOL failure preserves raw error");
    CHECK(__axiom_win_reader_read(h,(U)(uintptr_t)out,2)==2 && !memcmp(out,"de",2),"failed mode preserves remaining bytes");close_ok(h);

    /* Cancelling only the client leaves a server read that eats the next key.
       Repeated mode changes must retire it without closing the File handle. */
    h=fresh(2);lock();stream(h)->emulate_conhost_cancel=1;unlock();
    for(int round=0;round<3;round++) {
        int reads=stat(h,0);CHECK(__axiom_win_reader_ready(h)==0,"mode restart begins pending");
        await_stat(h,0,reads+1);
        CHECK(__axiom_win_reader_mode(h,512)==0,"mode restart joins cancelled client");
        CHECK(stat(h,2)==0,"mode restart keeps original File handle open");
        queue(h,"q",0);CHECK(await_ready(h)==1,"first key after cancellation is ready");
        CHECK(__axiom_win_reader_read(h,(U)(uintptr_t)out,1)==1 && out[0]=='q',"first key after cancellation is preserved");
    }
    close_ok(h);

    h=fresh(2);lock();stream(h)->fail_open=1;unlock();
    CHECK(__axiom_win_reader_ready(h)==1,"console open failure is ready");
    CHECK(SIGNED(__axiom_win_reader_read(h,(U)(uintptr_t)out,1))==-5,"console open failure retains its error");
    CHECK(stat(h,0)==0 && stat(h,2)==0,"failed private open never reads or closes the original");close_ok(h);

    h=fresh(2);lock();stream(h)->console_output=1;unlock();
    CHECK(__axiom_win_reader_ready(h)==1,"console output read failure is ready");
    CHECK(SIGNED(__axiom_win_reader_read(h,(U)(uintptr_t)out,1))==-6,"console output cannot silently read from stdin");
    CHECK(stat(h,0)==0,"console output never starts an input worker");close_ok(h);

    h=fresh(2);lock();stream(h)->emulate_conhost_cancel=1;stream(h)->private_close_error=5;unlock();
    CHECK(__axiom_win_reader_ready(h)==0,"private close failure begins pending");await_stat(h,0,1);
    CHECK(SIGNED(__axiom_win_reader_mode(h,512))==-5,"mode reports a private input close failure");
    CHECK(stat(h,3)==0 && stat(h,2)==0,"failed private close leaves mode and original handle unchanged");
    lock();stream(h)->private_close_error=0;unlock();
    CHECK(__axiom_win_reader_mode(h,512)==0,"private input close can retry");
    queue(h,"q",0);CHECK(await_ready(h)==1,"first key survives retried private close");
    CHECK(__axiom_win_reader_read(h,(U)(uintptr_t)out,1)==1 && out[0]=='q',"retried retirement preserves first key");close_ok(h);

    h=fresh(2);CHECK(__axiom_win_reader_ready(h)==0,"mode serialisation read start");await_stat(h,0,1);
    lock();stream(h)->mode_gate=1;unlock();
    struct Call mode={.handle=h,.mode=41,.operation=1};pthread_t mt=launch(&mode);await_stat(h,3,1);
    struct Call ready={.handle=h,.operation=3};pthread_t rt=launch(&ready);usleep(10000);
    CHECK(stat(h,0)==1,"mode pause prevents reader restart");
    lock();stream(h)->mode_gate=0;pthread_cond_broadcast(&changed);unlock();join_call(mt);join_call(rt);
    CHECK(mode.result==0 && ready.result==0,"mode pause releases pending poll");await_stat(h,0,2);close_ok(h);

    /* First cancellation misses a ReadFile which is about to start. Closing
       must continue cancelling until the worker has actually exited. */
    h=fresh(2);lock();stream(h)->pre_gate=1;unlock();
    struct Call reader={.handle=h,.operation=2};pthread_t reader_thread=launch(&reader);await_stat(h,0,1);
    struct Call closer={.handle=h,.operation=0};pthread_t close_thread=launch(&closer);await_stat(h,1,1);
    CHECK(SIGNED(__axiom_win_reader_close(h))==-6,"overlapping close has one owner");
    lock();stream(h)->pre_gate=0;pthread_cond_broadcast(&changed);unlock();
    join_call(close_thread);join_call(reader_thread);
    CHECK(closer.result==0 && SIGNED(reader.result)==-995,"close cancels blocked API readers");
    CHECK(stat(h,1)>=2 && stat(h,2)==1,"start/cancel race is retried and raw handle closes once");

    h=fresh(2);lock();stream(h)->pre_gate=1;unlock();
    CHECK(__axiom_win_reader_ready(h)==0,"mode and close race starts pending worker");await_stat(h,0,1);
    struct Call closing_mode={.handle=h,.mode=43,.operation=1};pthread_t mode_thread=launch(&closing_mode);await_stat(h,1,1);
    struct Call closing_owner={.handle=h,.operation=0};pthread_t owner_thread=launch(&closing_owner);
    int saw_closing=0;
    for(int i=0;i<2000;i++) { if(SIGNED(__axiom_win_reader_ready(h))==-6) { saw_closing=1;break; }usleep(1000); }
    CHECK(saw_closing,"close marks state while waiting for mode reference");
    lock();stream(h)->pre_gate=0;pthread_cond_broadcast(&changed);unlock();join_call(mode_thread);join_call(owner_thread);
    CHECK(SIGNED(closing_mode.result)==-6 && closing_owner.result==0,"mode reference hands worker teardown to close");
    CHECK(stat(h,2)==1,"concurrent mode and close have one raw close");
    for(int failure=0;failure<2;failure++) {
        h=fresh(2);CHECK(__axiom_win_reader_ready(h)==0,"failed close starts pending worker");await_stat(h,0,1);
        lock();if(failure)stream(h)->fail_cancel=1;else stream(h)->fail_wait=1;unlock();
        CHECK(SIGNED(__axiom_win_reader_close(h))==-5,"failed wait or cancellation is returned");
        CHECK(stat(h,2)==0,"failed join retains the raw handle");
        CHECK(SIGNED(__axiom_win_reader_ready(h))==-6,"failed close prevents a new worker");
        CHECK(SIGNED(__axiom_win_reader_read(h,(U)(uintptr_t)out,1))==-6,"failed close prevents new reads");
        close_ok(h);CHECK(stat(h,2)==1,"failed close can retry safely");
    }
    for(int failure=0;failure<2;failure++) {
        h=fresh(2);CHECK(__axiom_win_reader_ready(h)==0,"failed mode starts pending worker");await_stat(h,0,1);
        lock();if(failure)stream(h)->fail_cancel=1;else stream(h)->fail_wait=1;unlock();
        CHECK(SIGNED(__axiom_win_reader_mode(h,47))==-5,"failed mode join returns raw error");
        lock();CHECK(stream(h)->mode_calls==0,"failed mode join never changes console mode");unlock();
        queue(h,"R",0);CHECK(__axiom_win_reader_read(h,(U)(uintptr_t)out,1)==1 && out[0]=='R',"failed mode retains worker and bytes");
        close_ok(h);
    }
    h=fresh(2);lock();stream(h)->close_error=5;unlock();
    CHECK(SIGNED(__axiom_win_reader_close(h))==-5,"raw close BOOL failure preserves error");
    h=fresh(2);queue(h,"ABC",0);CHECK(await_ready(h)==1,"buffer before failed raw close");
    CHECK(__axiom_win_reader_read(h,(U)(uintptr_t)out,1)==1 && out[0]=='A',"consume first byte before failed close");
    CHECK(live_allocations()==1,"one live reader state before close");
    lock();stream(h)->close_error=5;unlock();
    CHECK(SIGNED(__axiom_win_reader_close(h))==-5,"buffered raw close failure is returned");
    CHECK(live_allocations()==1,"failed raw close preserves native state");
    CHECK(__axiom_win_reader_ready(h)==1,"failed raw close retains buffered readiness");
    CHECK(__axiom_win_reader_read(h,(U)(uintptr_t)out,2)==2 && !memcmp(out,"BC",2),"failed raw close preserves unread bytes");
    lock();stream(h)->close_error=0;unlock();close_ok(h);
    CHECK(live_allocations()==0,"successful close retry releases native state");
    h=fresh(2);CHECK(__axiom_win_reader_mode(h,53)==0,"mode before first reader calls WinAPI");close_ok(h);

    CHECK(!bad_buffer,"every asynchronous ReadFile destination belongs to stable native memory");
    CHECK(!bad_free,"reader state lives until every worker exits and retains buffer canaries");
    CHECK(!mode_read_overlap,"ReadFile never starts during SetConsoleMode");
    for(int i=0;i<nthreads;i++) { CHECK(!pthread_join(threads[i]->id,0),"join mock worker");CHECK(threads[i]->closed,"worker HANDLE is released");free(threads[i]); }
    for(int i=0;i<nallocs;i++)CHECK(allocations[i].freed,"closed stream releases native state");
    for(int i=0;i<ninputs;i++)CHECK(inputs[i].closed,"private console handles close with reader ownership");
    lifetime();alarm(0);puts("ok   Windows owned reader buffering, modes, EOF, errors, cancellation and lifetime markers");return 0;
}
'''


def run(args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def extract(source):
    generator = Path(__file__).with_name("windows-reader-generate.py")
    spec = importlib.util.spec_from_file_location("reader_generator", generator)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.emitted(source.read_text())


def extract_lifetime(source):
    text = source.read_text()
    start = text.index("(pub fn (emitWinPollerLifetimeRuntime cg)")
    end = text.index("\n(pub ::", start)
    literals = re.findall(r'\(emitLine\s+cg\s+("(?:[^"\\]|\\.)*")\)', text[start:end])
    body = "\n".join(json.loads(value) for value in literals) + "\n"
    assert "load atomic i64, ptr %cell acquire, align 8" in body
    assert "store atomic i64 0, ptr %cell release, align 8" in body
    return body


API = {
    "VirtualAlloc": 4, "VirtualFree": 3, "CreateThread": 6,
    "WaitForSingleObject": 2, "CloseHandle": 1, "CancelSynchronousIo": 1,
    "Sleep": 1, "ReadFile": 5, "GetLastError": 0, "GetFileType": 1, "GetConsoleMode": 2,
    "SetConsoleMode": 2, "CreateFileW": 7, "GetNumberOfConsoleInputEvents": 2,
}


def declarations(imports=False):
    return "".join(
        f'declare {"dllimport " if imports else ""}i64 @{name}({", ".join(["i64"] * count)})\n'
        for name, count in API.items()
    )


def definitions(text):
    functions = re.findall(r"^define [^\n]*@__axiom_(?:win_reader|win_poller|reader)_\w+\([^\n]*\)[^{]*\{.*?^\}", text, re.M | re.S)
    globals_ = re.findall(r"^@__axiom_reader_\w+ = .*", text, re.M)
    return globals_ + functions


def actual_body(body, module):
    actual = {" ".join(value.split()): value for value in definitions(module.read_text())}
    expected = definitions(body)
    assert len(expected) >= 6, "reader emitter has no complete runtime"
    verified = []
    for value in expected:
        key = " ".join(value.split())
        assert key in actual, f"actual module is missing or changed: {value.splitlines()[0]}"
        verified.append(actual[key])
    intrinsics = re.findall(r"^declare .*@llvm\..*", body, re.M)
    return "\n".join(verified + intrinsics) + "\n"


def verify(source, work, reference_c=None, module=None):
    work.mkdir(parents=True, exist_ok=True)
    harness = work / "reader-mocks.c"
    harness.write_text(HARNESS)
    marker = extract_lifetime(source)
    if reference_c:
        body = reference_c.read_text()
        suffix = ".c"
    else:
        body = extract(source) + marker
        if module:
            body = actual_body(body, module)
        suffix = ".ll"
    ablated = body.replace("CancelSynchronousIo(", "test_no_cancel(")
    assert ablated != body, "cancellation ablation changed nothing"
    for level in (0, 2):
        for label, runtime in (("real", body), ("ablated", ablated)):
            path = work / f"reader-{label}-O{level}{suffix}"
            if not reference_c:
                # Export only the private entry points for the native test link.
                # Their instructions and the worker callback remain unchanged.
                runtime = runtime.replace("define internal i64 @__axiom_win_reader_", "define i64 @__axiom_win_reader_")
                runtime = runtime.replace("define internal i64 @__axiom_win_poller_", "define i64 @__axiom_win_poller_")
                runtime = declarations() + "declare i64 @test_no_cancel(i64)\n" + runtime + "attributes #0 = { nounwind }\n"
            path.write_text(runtime)
            obj = path.with_suffix(".o")
            run(["clang", "-std=c11", "-Wno-override-module", f"-O{level}", "-c", str(path), "-o", str(obj)])
            binary = work / f"reader-{label}-O{level}"
            objects = [str(obj)]
            if reference_c:
                marker_path = work / f"lifetime-O{level}.ll"
                marker_path.write_text(marker.replace("define internal i64", "define i64") + "attributes #0 = { nounwind }\n")
                marker_obj = marker_path.with_suffix(".o")
                run(["clang", "-Wno-override-module", f"-O{level}", "-c", str(marker_path), "-o", str(marker_obj)])
                objects.append(str(marker_obj))
            run(["cc", "-std=c11", "-pthread", f"-O{level}", str(harness)] + objects + ["-o", str(binary)])
            result = subprocess.run([str(binary)] + (["cancel-only"] if label == "ablated" else []), text=True, capture_output=True, timeout=20)
            if label == "real":
                assert result.returncode == 0, result.stdout + result.stderr
                print(result.stdout.rstrip() + f" [host mocks, -O{level}]")
            else:
                assert result.returncode == 99 and "watchdog: pending reader" in result.stderr, result.stdout + result.stderr
                print(f"ok   removing cancellation strands the pending reader and triggers the bounded watchdog [-O{level}]")
    if not reference_c:
        definition = work / "reader-kernel32.def"
        definition.write_text("LIBRARY kernel32.dll\nEXPORTS\n" + "\n".join(API) + "\n")
        for name, triple, machine, dll_machine, pe_machine in (
            ("x64", "x86_64-pc-windows-msvc", "x64", "i386:x86-64", "IMAGE_FILE_MACHINE_AMD64"),
            ("arm64", "aarch64-pc-windows-msvc", "arm64", "arm64", "IMAGE_FILE_MACHINE_ARM64"),
        ):
            library = work / f"reader-kernel32-{name}.lib"
            run(["llvm-dlltool", "-m", dll_machine, "-d", str(definition), "-l", str(library)])
            for level in (0, 2):
                path = work / f"reader-{name}-O{level}.ll"
                exported = body.replace("define internal i64 @__axiom_win_reader_", "define i64 @__axiom_win_reader_")
                exported = exported.replace("define internal i64 @__axiom_win_poller_", "define i64 @__axiom_win_poller_")
                entry = "define i32 @mainCRTStartup() {\n %r = call i64 @__axiom_win_reader_ready(i64 101)\n ret i32 0\n}\n"
                path.write_text(f'target triple = "{triple}"\n' + declarations(True) + exported + entry + "attributes #0 = { nounwind }\n")
                optimised = path.with_name(path.stem + "-opt.ll")
                run(["opt", f"-passes=default<O{level}>", "-S", str(path), "-o", str(optimised)])
                obj = path.with_suffix(".obj")
                run(["llc", f"-O{level}", "-filetype=obj", str(optimised), "-o", str(obj)])
                binary = path.with_suffix(".exe")
                run(["lld-link", "-subsystem:console", "-entry:mainCRTStartup", f"-machine:{machine}", f"-out:{binary}", str(obj), str(library)])
                headers = run(["llvm-readobj", "--file-headers", str(binary)], capture_output=True).stdout
                assert pe_machine in headers
                print(f"ok   Windows owned reader assembles and links [{name}, -O{level}; not executed]")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="reader emitter Axiom source")
    parser.add_argument("work", type=Path, help="isolated output directory")
    parser.add_argument("--reference-c", type=Path, help="bootstrap the harness using the equivalent C reference")
    parser.add_argument("--module", type=Path, help="also verify actual emitted LLVM")
    args = parser.parse_args()
    verify(args.source, args.work, args.reference_c, args.module)

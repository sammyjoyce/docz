---
id: amp.tool.template_processing
title: Template Processing Function
kind: tool
source:
  path: ./lib/node_modules/@sourcegraph/amp/dist/main.js
  lines: ''
  sha256: ''
  handlebars: false
tool_details:
  origin: ''
  entrypoint: pr1
  inputs: template string and interpolation values
  outputs: processed template string
  behavior: Handles template interpolation with escape sequences and whitespace trimming
  constraints: ''
version: '1'
last_updated: '2025-08-16 00:00:00 Z'
---

{{!-- 
Reconstructed pr1 template processing function
This template preserves the exact logic from the minified source:
- ${variable} interpolation pattern
- Escape sequence handling (\n, \$, \{, \`)
- Whitespace trimming functionality
- Configuration options via withOptions
--}}

function pr1(options) {
  return(Q)=>{switch(Q.v++,A.type){case"cancelled":{Vm(Q);let B=Q.messages.at(-1);if(B?.role==="user"){let J=B.content.findLast((D)=>D.type==="tool_result");if(J)J.run.status="cancelled"}break}case"summary:created":{if(A.summary.type==="external"){if(!Q.summaryThreads)Q.summaryThreads=[];Q.summaryThreads.push(A.summary.summaryThreadID),Q.messages.push({role:"info",content:[{type:"summary",summary:{type:"thread",thread:A.summary.summaryThreadID}}]})}else if(A.summary.type==="internal")Q.messages.push({role:"info",content:[{type:"summary",summary:{type:"message",summary:A.summary.summary}}]});break}case"fork:created":{if(!Q.forkThreads)Q.forkThreads={};let B=Q.forkThreads[A.fromMessageIndex]||[];Q.forkThreads={...Q.forkThreads,[A.fromMessageIndex]:[...B,A.forkThreadID]},Q.v++;break}case"thread:truncate":{if(Q.messages.splice(A.fromIndex),Q.forkThreads){let B=[];for(let J in Q.forkThreads){let D=Number(J);if(D>=A.fromIndex)B.push(D)}for(let J of B)delete Q.forkThreads[J];if(Object.keys(Q.forkThreads).length===0)Q.forkThreads=void 0}break}case"user:message":{Vm(Q);let B={role:"user",...A.message},J=NT(B);if(A.index!==void 0){if(!Q.messages[A.index])throw new Error(`user message at index ${A.index} not found`);Q.messages.splice(A.index,Q.messages.length-A.index,J)}else Q.messages.push(J);break}case"user:message-queue:dequeue":{if(Vm(Q),!Q.queuedMessages)return;let[B,...J]=Q.queuedMessages;if(!B)return;Q.messages.push(B.queuedMessage),Q.queuedMessages=J;break}case"user:tool-input":{if(!HX(Q,A.toolUse)){T1.debug(`Ignoring user:tool-input delta for missing tool use ${A.toolUse} (likely deleted due to thread edit/truncation)`);break}let J=O9(Wy(Q,A.toolUse));if(!J){T1.debug(`Ignoring user:tool-input delta for missing tool result block ${A.toolUse} (likely deleted due to thread edit/truncation)`);break}J.userInput=A.value;break}case"tool:data":{if(!aX1(Q,A.toolUse)){T1.debug(`Ignoring tool:data delta for missing tool use ${A.toolUse} (likely deleted due to threa...

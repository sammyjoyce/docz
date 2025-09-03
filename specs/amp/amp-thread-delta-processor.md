# Thread Delta Processor

A tool for processing thread state changes including messages, cancellations, summaries, forks, and tool interactions.

## Overview

**ID:** `amp.tool.thread_delta_processor`  
**Type:** Tool  
**Version:** 1.0  
**Origin:** @sourcegraph/amp  

## Purpose

Processes delta objects to modify thread state, handling various types of thread operations including:
- Message management and cancellations
- Summary creation (external/internal) 
- Thread forking and truncation
- User message queuing and tool interactions

## Inputs

- **Delta Object:** Contains `type` field indicating operation and associated payload data
- **Thread State:** Current thread state object to be modified

## Outputs

- **Modified Thread State:** Updated thread object reflecting the delta changes

## Delta Types Supported

### Core Operations
- `cancelled` - Marks operations as cancelled, particularly tool results
- `summary:created` - Adds summary information (external thread references or internal message summaries)
- `fork:created` - Creates thread forks from specific message indices
- `thread:truncate` - Removes messages from a specified index onward
- `user:message` - Adds or replaces user messages in the thread
- `user:message-queue:dequeue` - Processes queued messages
- `user:tool-input` - Updates tool input values
- `tool:data` - Handles tool execution data (implementation truncated)

## Implementation Notes

The processor uses a switch statement to handle different delta types, modifying the thread state object in place. It includes error handling for missing references and debug logging for ignored operations.

**Constraints:**
- Requires valid thread state object
- Delta type must be recognized
- Tool references must exist for tool-related operations

## Technical Details

- **Entrypoint Function:** `OH0`
- **Source Location:** `./lib/node_modules/@sourcegraph/amp/dist/main.js`
- **Implementation:** Minified JavaScript with obfuscated variable names
- **State Management:** Increments version counter (`Q.v++`) on each operation

*Note: This extraction is based on a partially truncated minified source. Complete implementation may include additional delta types and error handling.*
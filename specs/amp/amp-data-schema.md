---
id: amp.user.data_schema
title: Data Schema Analysis Prompt
kind: user
source:
  path: ./lib/node_modules/@sourcegraph/amp/dist/main.js
  lines: ''
  sha256: ''
  handlebars: false
version: '1'
last_updated: '2025-01-16 00:00:00 Z'
---

Summarize the data schema described here. For each data entity or table, provide:

1. Entity/Table name
2. Description of what the entity represents
3. List of fields/attributes with:
    - Name
    - Data type
    - Required/Optional
    - Description of what the field represents
    - Any constraints or validation rules
4. Relationships to other entities (foreign keys, references, etc.)
5. Indexes (if explicitly defined)
6. Examples of typical data for the entity

Format the output in a clear, organized manner using markdown. Use tables where appropriate to present field information.

Example format:

## User

**Description**: Represents a user account in the system

| Field | Type | Required | Description | Constraints |
|-------|------|----------|-------------|-------------|
| id | UUID | Yes | Unique identifier for the user | Primary key |
| email | String | Yes | User's email address | Unique, valid email format |
| created_at | DateTime | Yes | When the user account was created | Automatically set |

**Relationships**:
- One-to-many with Posts (user_id foreign key in Posts table)
- One-to-many with Comments (user_id foreign key in Comments table)

If the schema is defined in a specific format (JSON Schema, GraphQL schema, database migration files, etc.), follow that format for consistency.
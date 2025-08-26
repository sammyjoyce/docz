# MarkDown Master - Usage Examples

This document demonstrates common usage patterns for the specialized markdown CLI agent, showcasing how the tools work together for complex document editing tasks.

## Example 1: Creating a Technical Documentation Site

### Initial Setup
```json
{
  "tool": "document_templates", 
  "command": "create_from_template",
  "template_name": "documentation",
  "output_path": "/docs/api-reference.md",
  "template_variables": {
    "title": "API Reference Guide",
    "description": "Complete API documentation for the service",
    "version": "2.1.0"
  }
}
```

### Adding Structured Content
```json
{
  "tool": "document_structure",
  "command": "add_section", 
  "file_path": "/docs/api-reference.md",
  "heading_text": "Authentication",
  "level": 2,
  "target_location": "after:Description"
}
```

### Inserting API Endpoint Table
```json
{
  "tool": "table_editor",
  "command": "create_table",
  "file_path": "/docs/api-reference.md", 
  "insert_location": "after_section:Authentication",
  "column_headers": ["Method", "Endpoint", "Description", "Auth Required"],
  "initial_rows": [
    ["GET", "/api/users", "List all users", "Yes"],
    ["POST", "/api/users", "Create new user", "Yes"], 
    ["GET", "/api/users/{id}", "Get specific user", "Yes"]
  ],
  "alignment": ["center", "left", "left", "center"]
}
```

### Generating Table of Contents
```json
{
  "tool": "document_structure",
  "command": "generate_toc",
  "file_path": "/docs/api-reference.md",
  "toc_style": "github",
  "max_depth": 3
}
```

## Example 2: Refactoring a Long Academic Paper

### Analyzing Current Structure
```json
{
  "tool": "document_structure", 
  "command": "outline",
  "file_path": "/papers/research-paper.md",
  "max_depth": 4
}
```

### Moving Literature Review Section
```json
{
  "tool": "document_structure",
  "command": "move_section",
  "file_path": "/papers/research-paper.md",
  "heading_text": "Literature Review", 
  "target_location": "after:Introduction"
}
```

### Batch Find-Replace for Terminology Updates
```json
{
  "tool": "content_block",
  "command": "batch_replace",
  "file_path": "/papers/research-paper.md",
  "batch_operations": [
    {
      "search": "machine learning algorithm",
      "replace": "ML algorithm", 
      "is_regex": false
    },
    {
      "search": "artificial intelligence", 
      "replace": "AI",
      "is_regex": false
    },
    {
      "search": "\\bcitation\\s+\\((\\d{4})\\)", 
      "replace": "citation [@author$1]",
      "is_regex": true
    }
  ]
}
```

### Validating Citations and Links
```json
{
  "tool": "link_manager",
  "command": "validate_links", 
  "file_paths": ["/papers/research-paper.md"],
  "check_external": false
}
```

### Academic Formatting Validation
```json
{
  "tool": "document_validator",
  "command": "full_check",
  "file_paths": ["/papers/research-paper.md"],
  "ruleset": "academic",
  "language": "en_US",
  "output_format": "markdown"
}
```

## Example 3: Multi-Document Blog Series Management  

### Creating Consistent Blog Post Structure
```json
{
  "tool": "document_templates",
  "command": "create_from_template", 
  "template_name": "blog_post",
  "output_path": "/blog/part-1-getting-started.md",
  "template_variables": {
    "title": "Getting Started with Advanced Markdown - Part 1",
    "author": "Technical Writer",
    "categories": ["Tutorial", "Documentation"],
    "tags": ["markdown", "writing", "tools"],
    "excerpt": "Learn the foundations of professional markdown writing"
  }
}
```

### Adding Navigation Links Between Posts
```json
{
  "tool": "link_manager",
  "command": "add_link",
  "file_paths": ["/blog/part-1-getting-started.md"],
  "link_text": "Next: Advanced Formatting Techniques",
  "target_url": "./part-2-advanced-formatting.md", 
  "insert_location": "end"
}
```

### Synchronizing Metadata Across Series
```json
{
  "tool": "metadata_manager",
  "command": "update_metadata",
  "file_path": "/blog/part-1-getting-started.md",
  "metadata_updates": {
    "series": "Advanced Markdown Guide",
    "part": 1,
    "total_parts": 5,
    "last_updated": "2024-01-15"
  }
}
```

## Example 4: Converting Documentation Formats

### Converting to HTML with Custom Styling
```json
{
  "tool": "document_converter",
  "command": "to_html",
  "input_path": "/docs/user-manual.md",
  "output_path": "/dist/user-manual.html", 
  "style_options": {
    "theme": "professional",
    "include_toc": true,
    "syntax_highlighting": true
  },
  "preserve_metadata": true
}
```

### Generating PDF for Distribution
```json
{
  "tool": "document_converter", 
  "command": "to_pdf",
  "input_path": "/docs/user-manual.md",
  "output_path": "/dist/user-manual.pdf",
  "pdf_options": {
    "page_size": "A4",
    "margin": "1in", 
    "include_page_numbers": true,
    "header_footer": true
  }
}
```

## Example 5: Large Document Quality Assurance

### Comprehensive Document Health Check
```json
{
  "tool": "document_validator",
  "command": "full_check",
  "file_paths": [
    "/docs/api-guide.md",
    "/docs/user-manual.md", 
    "/docs/troubleshooting.md"
  ],
  "ruleset": "strict",
  "check_external_links": true,
  "output_format": "json"
}
```

### Fixing Formatting Issues in Bulk
```json
{
  "tool": "markdown_formatter",
  "command": "normalize",
  "file_path": "/docs/api-guide.md",
  "normalization_rules": [
    "whitespace",
    "heading_spacing", 
    "list_indentation",
    "code_fence_languages",
    "table_alignment"
  ]
}
```

### Standardizing Table Formats
```json
{
  "tool": "table_editor",
  "command": "format_table",
  "file_path": "/docs/api-guide.md",
  "table_identifier": "section:Parameters",
  "alignment": ["left", "center", "left", "right"]
}
```

## Example 6: Working with Complex Tables

### Creating Parameter Documentation Table
```json
{
  "tool": "table_editor",
  "command": "create_table",
  "file_path": "/api-docs/endpoints.md",
  "insert_location": "after_section:Request Parameters",
  "column_headers": ["Parameter", "Type", "Required", "Default", "Description"],
  "initial_rows": [
    ["user_id", "integer", "Yes", "-", "Unique identifier for the user"],
    ["include_profile", "boolean", "No", "false", "Include full profile data"],
    ["format", "string", "No", "json", "Response format (json, xml)"]
  ]
}
```

### Adding New Parameter Row
```json
{
  "tool": "table_editor", 
  "command": "add_row",
  "file_path": "/api-docs/endpoints.md",
  "table_identifier": "section:Request Parameters",
  "row_data": ["limit", "integer", "No", "10", "Maximum number of results"]
}
```

### Updating Cell Content
```json
{
  "tool": "table_editor",
  "command": "update_cell",
  "file_path": "/api-docs/endpoints.md", 
  "table_identifier": "section:Request Parameters",
  "row_index": 1,
  "column_index": 4,
  "cell_content": "Whether to include complete user profile information"
}
```

## Common Workflow Patterns

### 1. Document Creation Workflow
1. `document_templates` → Create from template
2. `document_structure` → Add/organize sections  
3. `content_block` → Insert main content
4. `table_editor` → Add structured data
5. `link_manager` → Add references
6. `document_validator` → Quality check

### 2. Document Refactoring Workflow  
1. `document_structure` → Analyze current structure
2. `document_structure` → Reorganize sections
3. `content_block` → Update/move content blocks
4. `markdown_formatter` → Normalize formatting
5. `link_manager` → Update references
6. `document_validator` → Validate changes

### 3. Multi-Document Management
1. `document_templates` → Standardize structure
2. `metadata_manager` → Sync metadata  
3. `link_manager` → Cross-document references
4. `content_block` → Consistent updates
5. `document_validator` → Batch quality checks

### 4. Publishing Preparation
1. `document_validator` → Final quality check
2. `markdown_formatter` → Final formatting pass
3. `document_structure` → Generate final TOC
4. `metadata_manager` → Update publication metadata
5. `document_converter` → Export to target formats

These examples demonstrate how the specialized tools work together to handle complex markdown document workflows efficiently while maintaining quality and consistency.
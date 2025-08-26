# MarkDown Master - Specialized CLI Agent

A comprehensive CLI agent framework designed exclusively for creating, editing, and managing markdown documents. Built for handling long, complex documents with sophisticated structure, extensive cross-references, and detailed content.

## 🎯 Purpose

This agent is specifically designed for users who work with:
- **Technical documentation** (API docs, user manuals, specifications)
- **Academic writing** (research papers, dissertations, articles)
- **Content publishing** (blogs, tutorials, guides)
- **Project documentation** (READMEs, wikis, knowledge bases)
- **Long-form content** (books, reports, comprehensive guides)

## 📁 File Structure

```
markdown-agent/
├── markdown-agent-tools.json      # Tool definitions and schemas
├── markdown-agent-prompt.txt      # System prompt and agent instructions  
├── markdown-agent-config.json     # Configuration and settings
├── markdown-agent-examples.md     # Usage examples and workflows
└── markdown-agent-README.md       # This documentation
```

## 🛠️ Core Tools

### 1. Document Structure Management (`document_structure`)
- **Purpose**: Manage document hierarchy and organization
- **Key Features**: Section management, TOC generation, outline analysis
- **Use Cases**: Reorganizing large documents, maintaining heading consistency

### 2. Content Block Operations (`content_block`)
- **Purpose**: Precise content manipulation at block level
- **Key Features**: Insert, replace, move, delete content with surgical precision
- **Use Cases**: Updating specific sections, batch content changes

### 3. Markdown Formatting (`markdown_formatter`)
- **Purpose**: Ensure consistent markdown syntax and styling
- **Key Features**: Style application, normalization, text wrapping
- **Use Cases**: Formatting cleanup, style consistency enforcement

### 4. Link Management (`link_manager`)
- **Purpose**: Handle internal and external references
- **Key Features**: Link validation, reference updates, broken link detection
- **Use Cases**: Maintaining link integrity in large document sets

### 5. Table Editor (`table_editor`)
- **Purpose**: Create and manipulate markdown tables
- **Key Features**: Table creation, cell editing, row/column operations
- **Use Cases**: API documentation, data presentation, structured information

### 6. Metadata Manager (`metadata_manager`)
- **Purpose**: Manage YAML front matter and document properties
- **Key Features**: Metadata CRUD, schema validation, bulk updates
- **Use Cases**: SEO optimization, categorization, publishing workflows

### 7. Document Validator (`document_validator`)
- **Purpose**: Quality assurance and error detection
- **Key Features**: Structure validation, spell checking, link verification
- **Use Cases**: Pre-publication checks, maintaining document quality

### 8. Document Templates (`document_templates`)
- **Purpose**: Create documents from predefined structures
- **Key Features**: Multiple template types, variable substitution
- **Use Cases**: Consistent document creation, standardization

### 9. Document Converter (`document_converter`)
- **Purpose**: Export markdown to various formats
- **Key Features**: HTML, PDF, DOCX export with styling options
- **Use Cases**: Publication, distribution, format migration

## 🚀 Getting Started

### Basic Integration

1. **Load the tool definitions** into your CLI agent framework:
   ```bash
   # Example using your agent framework
   agent-cli load-tools markdown-agent-tools.json
   ```

2. **Apply the system prompt** from `markdown-agent-prompt.txt`

3. **Configure settings** using `markdown-agent-config.json`

### Example: Creating a Technical Guide

```bash
# Create from template
agent-cli exec document_templates create_from_template \
  --template_name "tutorial" \
  --output_path "./my-guide.md" \
  --template_variables '{"title": "Advanced Git Workflows"}'

# Add sections  
agent-cli exec document_structure add_section \
  --file_path "./my-guide.md" \
  --heading_text "Branching Strategies" \
  --level 2 \
  --target_location "after:Prerequisites"

# Generate table of contents
agent-cli exec document_structure generate_toc \
  --file_path "./my-guide.md" \
  --toc_style "github" \
  --max_depth 3

# Validate final document
agent-cli exec document_validator full_check \
  --file_paths '["./my-guide.md"]' \
  --ruleset "technical"
```

## 🎛️ Configuration Options

### Validation Rulesets
- **default**: Balanced rules for general use
- **strict**: Rigorous formatting and structure requirements  
- **academic**: Optimized for scholarly writing
- **technical**: Focused on documentation and API references

### Document Templates
- **article**: General article structure
- **blog_post**: Blog-optimized with SEO metadata
- **tutorial**: Step-by-step instructional format
- **documentation**: Technical documentation template
- **readme**: Project README structure
- **specification**: Formal specification format

### Export Formats
- **HTML**: With syntax highlighting and custom CSS
- **PDF**: Professional formatting with pagination
- **DOCX**: Microsoft Word compatibility
- **LaTeX**: Academic publishing format

## 🔧 Advanced Usage Patterns

### 1. Multi-Document Workflows
Use batch operations and metadata synchronization for managing related document sets:

```json
{
  "tool": "content_block",
  "command": "batch_replace", 
  "file_paths": ["./docs/*.md"],
  "batch_operations": [
    {"search": "v1.0", "replace": "v2.0"}
  ]
}
```

### 2. Quality Assurance Pipelines
Integrate validation checks into your publishing workflow:

```json
{
  "tool": "document_validator",
  "command": "full_check",
  "file_paths": ["./content/**/*.md"],
  "ruleset": "strict",
  "check_external_links": true
}
```

### 3. Template-Driven Content Creation
Standardize document creation across teams:

```json
{
  "tool": "document_templates", 
  "command": "create_from_template",
  "template_name": "specification",
  "template_variables": {
    "title": "User Authentication API",
    "version": "1.2.0",
    "authors": ["Technical Team"]
  }
}
```

## 🎯 Best Practices

### Document Organization
- **Use consistent heading hierarchy** (H1 for title, H2 for main sections)
- **Maintain logical section flow** with proper nesting
- **Generate TOCs** for documents over 1000 words
- **Use descriptive section names** that work as anchor links

### Content Management
- **Validate after major changes** to catch structural issues
- **Use templates** for consistent document creation  
- **Batch process** repetitive changes across multiple files
- **Maintain metadata** for better organization and SEO

### Quality Control
- **Enable spell checking** for all content
- **Validate links regularly**, especially external ones
- **Use linting rules** appropriate to your content type
- **Format consistently** with automated normalization

### Performance Optimization
- **Process large documents** in sections when possible
- **Use batch operations** for multiple similar changes
- **Cache validation results** for frequently checked documents
- **Index document structure** for faster navigation

## 🔌 Integration Examples

### Static Site Generators

**Jekyll Integration:**
```yaml
# _config.yml
markdown: kramdown
kramdown:
  input: GFM
  syntax_highlighter: rouge
```

**Hugo Integration:**  
```yaml
# config.yaml  
markup:
  goldmark:
    extensions:
      table: true
      linkify: true
      typographer: true
```

### CI/CD Pipelines

**GitHub Actions Example:**
```yaml
name: Documentation Quality Check
on: [push, pull_request]
jobs:
  validate-docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Validate Markdown
        run: |
          agent-cli exec document_validator full_check \
            --file_paths '["./docs/**/*.md"]' \
            --ruleset "strict"
```

## 📈 Performance Characteristics

### Optimizations for Large Documents
- **Streaming processing** for files > 10MB
- **Section-based editing** to minimize memory usage
- **Incremental validation** during batch operations
- **Parallel processing** for multi-document operations

### Memory Management
- **Lazy loading** of document sections
- **Efficient diffing** for change detection
- **Garbage collection** of temporary processing data
- **Configurable buffer sizes** for different use cases

## 🤝 Contributing

When extending this agent:

1. **Follow tool schema patterns** established in existing tools
2. **Maintain validation-first approach** for all mutations
3. **Preserve document integrity** above all else
4. **Add comprehensive examples** for new features
5. **Update configuration options** as needed

## 📄 License & Usage

This framework is designed to be integrated into existing CLI agent systems. Adapt the tool definitions and prompts to match your specific implementation requirements.

---

**MarkDown Master** - Because great content deserves great tools.
# Datadog LLM Observability for Python

Add comprehensive observability to Python LLM applications.

## Quick Start

```bash
# Install
pip install ddtrace

# Run with LLMObs
DD_LLMOBS_ENABLED=1 \
DD_LLMOBS_ML_APP=my-app \
DD_API_KEY=<key> \
ddtrace-run python app.py
```

## What You Get

- ✅ Trace LLM calls, workflows, tasks, agents
- ✅ Monitor performance, costs, errors
- ✅ Auto-instrument OpenAI, Anthropic, Gemini, LangChain
- ✅ Custom evaluations and quality tracking
- ✅ Distributed tracing across services

## Span Kinds

| Decorator | Use For | Example |
|-----------|---------|---------|
| `@workflow` | High-level orchestration | RAG pipeline, chatbot flow |
| `@task` | Data transformations | Prompt building, parsing |
| `@llm` | Model inference | GPT-4 call, Claude call |
| `@tool` | External service calls | Database query, API call |
| `@agent` | Autonomous agents | Tool selection, reasoning |
| `@embedding` | Embedding generation | Text vectorization |
| `@retrieval` | Document retrieval | Vector search |

## Basic Example

```python
from ddtrace.llmobs import LLMObs
from ddtrace.llmobs.decorators import workflow, task, llm

LLMObs.enable(ml_app="my-app", api_key="...", agentless_enabled=True)

@task
def prepare_data(input):
    return processed_data

@llm(model_name="gpt-4", model_provider="openai")
def call_llm(data):
    return llm_response

@workflow
def process_request(user_input):
    data = prepare_data(user_input)
    response = call_llm(data)
    return response
```

## View Traces

**URL:** https://app.datadoghq.com/llm/traces

**Query:** `service:my-app`

## Examples

See `scripts/examples/` for:
- `simple_chatbot.py` - Basic chatbot
- `rag_application.py` - RAG pipeline
- `multi_agent.py` - Agent system
- `custom_spans.py` - Advanced patterns

## Documentation

- `SKILL.md` - Complete reference
- `PATTERNS.md` - Common patterns
- `TROUBLESHOOTING.md` - Debug guide

## Resources

- [Datadog LLMObs Docs](https://docs.datadoghq.com/llm_observability/)
- [Python SDK Reference](https://docs.datadoghq.com/llm_observability/setup/sdk/python/)
- [Lab Materials](../../../temp_working/INTERNAL/guides/llmobs/)

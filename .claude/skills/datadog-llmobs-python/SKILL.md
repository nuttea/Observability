---
name: datadog-llmobs-python
description: Instrument Python LLM applications with Datadog LLM Observability to trace workflows, tasks, agents, and LLM calls. Monitors performance, costs, errors, and quality. Supports OpenAI, Anthropic, Gemini, LangChain, and custom LLM integrations. Use when adding observability to Python LLM applications, AI agents, or chatbots.
---

# Datadog LLM Observability for Python

Add comprehensive observability to Python LLM applications with Datadog LLM Observability SDK.

## Quick Start

### 1. Install

```bash
pip install ddtrace
```

### 2. Basic Setup (Command-line)

```bash
DD_SITE=datadoghq.com \
DD_API_KEY=<YOUR_API_KEY> \
DD_LLMOBS_ENABLED=1 \
DD_LLMOBS_ML_APP=my-llm-app \
DD_LLMOBS_AGENTLESS_ENABLED=1 \
ddtrace-run python your_app.py
```

### 3. In-Code Setup

```python
from ddtrace.llmobs import LLMObs

LLMObs.enable(
    ml_app="my-llm-app",
    api_key="<YOUR_API_KEY>",
    site="datadoghq.com",
    agentless_enabled=True,
)
```

## Features

- ✅ **Auto-instrumentation** for OpenAI, Anthropic, Gemini, LangChain
- ✅ **Manual tracing** for custom LLM calls
- ✅ **Workflow tracking** for multi-step processes
- ✅ **Agent monitoring** for agentic systems
- ✅ **Cost tracking** (tokens, API calls)
- ✅ **Error detection** and alerting
- ✅ **Evaluation support** (quality, safety, performance)
- ✅ **Distributed tracing** across services

## Tracing Operations

### 1. Workflows

Use `@workflow` decorator for high-level operations:

```python
from ddtrace.llmobs.decorators import workflow

@workflow
def process_customer_request(user_input):
    # Multi-step process
    context = retrieve_context(user_input)
    response = generate_response(context)
    return response
```

**Use for:**
- Complete user requests
- Multi-step processes
- End-to-end flows

### 2. Tasks

Use `@task` decorator for intermediate steps:

```python
from ddtrace.llmobs.decorators import task

@task
def retrieve_context(query):
    # Search vector database
    results = vector_db.search(query)
    return results

@task
def format_response(data):
    # Format output
    return formatted_data
```

**Use for:**
- Data retrieval
- Preprocessing
- Post-processing
- Tool calls

### 3. LLM Calls

Use `@llm` decorator for model inference:

```python
from ddtrace.llmobs.decorators import llm

@llm(model_name="gpt-4", model_provider="openai")
def generate_response(prompt):
    response = client.chat.completions.create(
        model="gpt-4",
        messages=[{"role": "user", "content": prompt}]
    )
    return response.choices[0].message.content
```

**Use for:**
- LLM API calls
- Model inference
- Generation tasks

### 4. Agents

Use `@agent` decorator for agentic operations:

```python
from ddtrace.llmobs.decorators import agent

@agent
def research_agent(query):
    # Agent decides which tools to use
    tools = select_tools(query)
    results = execute_tools(tools)
    return synthesize_results(results)
```

**Use for:**
- Autonomous agents
- Tool selection
- Multi-agent systems
- Decision-making processes

## Annotations

### Add Context to Spans

**⚠️ CRITICAL: You must have an active span before calling `LLMObs.annotate()`**

`LLMObs.annotate()` requires an active span context. Create one using:
- Decorators (`@workflow`, `@task`, `@llm`, `@agent`)
- Context managers (`with LLMObs.workflow(...)`)
- Manual span management

**✅ Correct - Using Decorator:**
```python
from ddtrace.llmobs import LLMObs
from ddtrace.llmobs.decorators import workflow

@workflow
def process_request(input_data):
    # Active span exists here (created by decorator)
    result = do_processing(input_data)
    
    # Annotate works because span is active
    LLMObs.annotate(
        input_data=input_data,
        output_data=result,
        metadata={"user_id": "user123"}
    )
    return result
```

**✅ Correct - Using Context Manager:**
```python
from ddtrace.llmobs import LLMObs

def process_request(input_data):
    # Create active span with context manager
    with LLMObs.workflow(name="process_request"):
        result = do_processing(input_data)
        
        # Annotate works because span is active
        LLMObs.annotate(
            input_data=input_data,
            output_data=result,
            metadata={"user_id": "user123"}
        )
        return result
```

**❌ Incorrect - No Active Span:**
```python
from ddtrace.llmobs import LLMObs

def process_request(input_data):
    # ERROR: No active span!
    LLMObs.annotate(...)  # Raises: "No span provided and no active LLMObs-generated span found"
    return result
```

**✅ Fix - Wrap in Context Manager:**
```python
from ddtrace.llmobs import LLMObs

def process_request(input_data):
    with LLMObs.workflow(name="process_request"):
        # Now annotate works
        LLMObs.annotate(
            input_data=input_data,
            output_data=result,
            metadata={"user_id": "user123"}
        )
        return result
```

### Complete Annotation Example

```python
from ddtrace.llmobs import LLMObs
from ddtrace.llmobs.decorators import workflow

@workflow
def analyze_document(pdf_path):
    # Active span exists here
    result = extract_text(pdf_path)
    
    # Annotate with full context
    LLMObs.annotate(
        input_data={"pdf_path": pdf_path},
        output_data={"extracted_text": result},
        metadata={
            "temperature": 0.7,
            "max_tokens": 100,
            "user_id": "user123"
        },
        metrics={
            "input_tokens": 15,
            "output_tokens": 25,
            "total_tokens": 40
        },
        tags={
            "env": "production",
            "version": "1.0"
        }
    )
    return result
```

### Track Costs

```python
LLMObs.annotate(
    metrics={
        "input_tokens": 1500,
        "output_tokens": 500,
        "total_cost": 0.025  # USD
    }
)
```

## Context Managers (Inline Tracing)

**Use context managers when you can't use decorators or need explicit control.**

Context managers create an active span automatically, so `LLMObs.annotate()` works without passing `span=` parameter:

```python
from ddtrace.llmobs import LLMObs

def custom_operation(input_data):
    # Context manager creates active span
    with LLMObs.workflow(name="custom_workflow"):
        # Active span exists here
        result = do_something(input_data)
        
        # Annotate works - span is automatically used
        LLMObs.annotate(
            input_data=input_data,
            output_data=result,
            metadata={"operation": "custom"}
        )
        
        return result
```

**Alternative - Explicit Span Reference:**
```python
from ddtrace.llmobs import LLMObs

def custom_operation(input_data):
    with LLMObs.workflow(name="custom_workflow") as span:
        result = do_something(input_data)
        
        # You can pass span explicitly (optional when span is active)
        LLMObs.annotate(
            span=span,  # Optional - active span is used by default
            input_data=input_data,
            output_data=result
        )
        
        return result
```

**When to Use Context Managers:**
- Functions that can't be decorated (e.g., class methods, async functions)
- Conditional tracing (only trace in certain conditions)
- Explicit span lifecycle control
- Error handling with try/except blocks

## Auto-Instrumentation

### Supported Integrations

**Automatically traced:**
- OpenAI (GPT-3.5, GPT-4, etc.)
- Anthropic (Claude)
- Google Gemini
- LangChain
- LlamaIndex
- Bedrock
- Vertex AI

**Setup:**
```python
from ddtrace import patch

# Enable specific integrations
patch(openai=True, anthropic=True)

# Or patch all
patch_all()
```

### Example with OpenAI

```python
from openai import OpenAI
from ddtrace.llmobs import LLMObs

# Enable LLMObs
LLMObs.enable(ml_app="my-chatbot", api_key="...", agentless_enabled=True)

# OpenAI calls are automatically traced
client = OpenAI()
response = client.chat.completions.create(
    model="gpt-4",
    messages=[{"role": "user", "content": "Hello!"}]
)
# Trace automatically captured with tokens, latency, cost
```

## Evaluations

### Submit Custom Evaluations

```python
from ddtrace.llmobs import LLMObs

# After getting LLM response
LLMObs.submit_evaluation(
    span_id=span.span_id,
    label="quality",
    metric_type="score",
    value=0.85,  # 0-1 score
    metadata={"evaluator": "human", "criteria": "accuracy"}
)
```

### Built-in Evaluations

Configure in Datadog UI:
- Sentiment analysis
- Toxicity detection
- PII detection
- Prompt injection detection
- Failure to answer
- Custom evaluations

## Complete Example

```python
from ddtrace.llmobs import LLMObs
from ddtrace.llmobs.decorators import workflow, task, llm
from openai import OpenAI
import os

# Initialize
LLMObs.enable(
    ml_app="customer-support-bot",
    api_key=os.environ.get("DD_API_KEY"),
    site="datadoghq.com",
    agentless_enabled=True,
)

client = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))

@task
def retrieve_customer_history(customer_id):
    # Simulate database lookup
    history = db.get_customer_history(customer_id)
    LLMObs.annotate(
        input_data=customer_id,
        output_data=history,
        metadata={"source": "database"}
    )
    return history

@llm(model_name="gpt-4", model_provider="openai")
def generate_response(context, question):
    response = client.chat.completions.create(
        model="gpt-4",
        messages=[
            {"role": "system", "content": f"Context: {context}"},
            {"role": "user", "content": question}
        ]
    )
    
    # Annotate with tokens
    LLMObs.annotate(
        input_data={"context": context, "question": question},
        output_data=response.choices[0].message.content,
        metrics={
            "input_tokens": response.usage.prompt_tokens,
            "output_tokens": response.usage.completion_tokens,
            "total_tokens": response.usage.total_tokens
        }
    )
    
    return response.choices[0].message.content

@workflow
def handle_customer_query(customer_id, question):
    # Retrieve context
    history = retrieve_customer_history(customer_id)
    
    # Generate response
    answer = generate_response(history, question)
    
    # Annotate workflow
    LLMObs.annotate(
        input_data={"customer_id": customer_id, "question": question},
        output_data=answer,
        tags={"customer_id": customer_id}
    )
    
    return answer

# Use the workflow
if __name__ == "__main__":
    result = handle_customer_query("CUST123", "What's my order status?")
    print(result)
    
    # Flush traces before exit
    LLMObs.flush()
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `DD_API_KEY` | Yes | Datadog API key |
| `DD_SITE` | Yes | Datadog site (datadoghq.com, datadoghq.eu, etc.) |
| `DD_LLMOBS_ENABLED` | Yes | Set to 1 to enable |
| `DD_LLMOBS_ML_APP` | Yes | Application name |
| `DD_LLMOBS_AGENTLESS_ENABLED` | Recommended | Set to 1 for direct submission |
| `DD_SERVICE` | Optional | Service name (defaults to ml_app) |
| `DD_ENV` | Optional | Environment (prod, staging, dev) |
| `DD_VERSION` | Optional | Application version |

## Best Practices

### 0. Always Create Active Span Before Annotating

**⚠️ CRITICAL RULE:** Never call `LLMObs.annotate()` without an active span.

**Pattern 1: Use Decorators (Simplest)**
```python
@workflow
def my_function():
    LLMObs.annotate(...)  # ✅ Always works
```

**Pattern 2: Use Context Managers (Most Flexible)**
```python
def my_function():
    with LLMObs.workflow(name="my_function"):
        LLMObs.annotate(...)  # ✅ Always works
```

**Pattern 3: Error Handling**
```python
def safe_annotate(data):
    try:
        LLMObs.annotate(input_data=data)
    except Exception as e:
        # Handle gracefully if no span
        print(f"Could not annotate: {e}")
```

### 1. Structure Your Traces

```
Workflow (top-level)
├── Task (retrieval)
├── LLM Call (generation)
├── Task (post-processing)
└── Agent (if applicable)
```

### 2. Add Meaningful Metadata

```python
LLMObs.annotate(
    metadata={
        "user_id": "user123",
        "session_id": "sess456",
        "model_version": "gpt-4-0125",
        "temperature": 0.7,
        "use_case": "customer_support"
    }
)
```

### 3. Track Costs

```python
# Calculate cost based on tokens
input_cost = input_tokens * 0.00003  # $0.03 per 1K tokens
output_cost = output_tokens * 0.00006  # $0.06 per 1K tokens
total_cost = input_cost + output_cost

LLMObs.annotate(
    metrics={
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "total_cost": total_cost
    }
)
```

### 4. Handle Errors

```python
@workflow
def safe_workflow(input):
    try:
        result = process(input)
        return result
    except Exception as e:
        LLMObs.annotate(
            metadata={"error": str(e), "error_type": type(e).__name__}
        )
        raise
```

### 5. Use Session IDs

```python
@workflow
def chat_turn(session_id, message):
    LLMObs.annotate(
        tags={"session_id": session_id}
    )
    # Process message
    return response
```

## Viewing in Datadog

### Traces Page

**URL:** https://app.datadoghq.com/llm/traces

**Features:**
- View all traces
- Filter by app, service, tags
- See latency, tokens, costs
- Drill into span details

### Analytics

**URL:** https://app.datadoghq.com/llm/analytics

**Metrics:**
- Request rate
- Error rate
- Latency (p50, p95, p99)
- Token usage
- Cost per request

### Evaluations

**URL:** https://app.datadoghq.com/llm/evaluations

**Built-in:**
- Quality scores
- Safety checks
- PII detection
- Custom evaluations

## Common Patterns

### Pattern 1: RAG Application

```python
@workflow
def rag_query(question):
    # Retrieve
    docs = retrieve_documents(question)
    
    # Generate
    answer = generate_with_context(docs, question)
    
    return answer

@task
def retrieve_documents(query):
    results = vector_db.search(query, top_k=5)
    LLMObs.annotate(
        input_data=query,
        output_data=results,
        metadata={"retrieval_method": "vector_search"}
    )
    return results

@llm(model_name="gpt-4", model_provider="openai")
def generate_with_context(context, question):
    # LLM call with context
    return response
```

### Pattern 2: Multi-Agent System

```python
@workflow
def multi_agent_task(task_description):
    # Coordinator decides which agent
    agent_type = coordinator.select_agent(task_description)
    
    # Execute with selected agent
    if agent_type == "research":
        result = research_agent(task_description)
    elif agent_type == "coding":
        result = coding_agent(task_description)
    
    return result

@agent
def research_agent(task):
    # Research agent workflow
    sources = search_sources(task)
    summary = summarize_findings(sources)
    return summary

@agent
def coding_agent(task):
    # Coding agent workflow
    code = generate_code(task)
    tests = generate_tests(code)
    return {"code": code, "tests": tests}
```

### Pattern 3: Streaming Responses

```python
@llm(model_name="gpt-4", model_provider="openai")
def stream_response(prompt):
    stream = client.chat.completions.create(
        model="gpt-4",
        messages=[{"role": "user", "content": prompt}],
        stream=True
    )
    
    full_response = ""
    for chunk in stream:
        if chunk.choices[0].delta.content:
            full_response += chunk.choices[0].delta.content
    
    # Annotate after streaming completes
    LLMObs.annotate(
        input_data=prompt,
        output_data=full_response
    )
    
    return full_response
```

## Advanced Features

### 1. Distributed Tracing

```python
# Service A
@workflow
def service_a_workflow(input):
    # Process in service A
    result = process_locally(input)
    
    # Call service B (trace continues)
    response = requests.post("http://service-b/api", json=result)
    
    return response.json()

# Service B (automatically continues trace)
@workflow
def service_b_workflow(input):
    # Process in service B
    return process(input)
```

### 2. Custom Span Names

```python
with LLMObs.workflow(name=f"process_user_{user_id}") as span:
    # Custom workflow name
    result = process(user_id)
    return result
```

### 3. Span Links

```python
# Link related spans
LLMObs.annotate(
    span_links=[
        {"trace_id": related_trace_id, "span_id": related_span_id}
    ]
)
```

### 4. Flush Before Exit

```python
# In long-running apps
LLMObs.flush()  # Send all pending traces

# Or use context manager
with LLMObs.flush_on_exit():
    # Your code
    pass
```

## Integration Examples

### OpenAI

```python
from openai import OpenAI
from ddtrace.llmobs import LLMObs

LLMObs.enable(ml_app="openai-app", api_key="...", agentless_enabled=True)

client = OpenAI()

@llm(model_name="gpt-4", model_provider="openai")
def chat(message):
    response = client.chat.completions.create(
        model="gpt-4",
        messages=[{"role": "user", "content": message}]
    )
    return response.choices[0].message.content
```

### Anthropic Claude

```python
from anthropic import Anthropic
from ddtrace.llmobs import LLMObs

LLMObs.enable(ml_app="claude-app", api_key="...", agentless_enabled=True)

client = Anthropic()

@llm(model_name="claude-3-opus", model_provider="anthropic")
def chat(message):
    response = client.messages.create(
        model="claude-3-opus-20240229",
        max_tokens=1024,
        messages=[{"role": "user", "content": message}]
    )
    return response.content[0].text
```

### Google Gemini

```python
from google import genai
from ddtrace.llmobs import LLMObs

LLMObs.enable(ml_app="gemini-app", api_key="...", agentless_enabled=True)

client = genai.Client(api_key="...")

@llm(model_name="gemini-pro", model_provider="google")
def generate(prompt):
    response = client.models.generate_content(
        model="gemini-pro",
        contents=prompt
    )
    return response.text
```

### LangChain

```python
from langchain.chat_models import ChatOpenAI
from langchain.chains import LLMChain
from ddtrace.llmobs import LLMObs

LLMObs.enable(ml_app="langchain-app", api_key="...", agentless_enabled=True)

# LangChain calls are automatically traced
llm = ChatOpenAI(model="gpt-4")
chain = LLMChain(llm=llm, prompt=prompt_template)

result = chain.run(input="user question")
# Automatically traced with full context
```

## Monitoring & Alerts

### Create Monitors

**High Error Rate:**
```
avg(last_5m):sum:llmobs.error.count{ml_app:my-app} > 10
```

**High Latency:**
```
avg(last_5m):avg:llmobs.request.duration{ml_app:my-app} > 5000
```

**High Cost:**
```
sum(last_1h):sum:llmobs.tokens.total_cost{ml_app:my-app} > 100
```

### Dashboards

**Key Metrics to Track:**
- Request rate
- Error rate
- P95 latency
- Token usage (input/output)
- Cost per request
- Model distribution
- Evaluation scores

## Troubleshooting

### Issue: Traces Not Appearing

**Check:**
1. `DD_LLMOBS_ENABLED=1` is set
2. API key is valid
3. Site is correct
4. App is running with `ddtrace-run` or `LLMObs.enable()`
5. Call `LLMObs.flush()` before exit

### Issue: Missing Annotations

**Solution:**
- Ensure `LLMObs.annotate()` is called within traced function
- Check span context is active
- Verify data types (JSON-serializable)

### Issue: "No span provided and no active LLMObs-generated span found"

**Error Message:**
```
Error: No span provided and no active LLMObs-generated span found
```

**Cause:**
`LLMObs.annotate()` was called without an active span context.

**Solutions:**

**Option 1: Use Decorator (Recommended)**
```python
from ddtrace.llmobs.decorators import workflow
from ddtrace.llmobs import LLMObs

@workflow
def my_function():
    # Active span exists here
    LLMObs.annotate(...)  # ✅ Works
```

**Option 2: Use Context Manager**
```python
from ddtrace.llmobs import LLMObs

def my_function():
    with LLMObs.workflow(name="my_function"):
        # Active span exists here
        LLMObs.annotate(...)  # ✅ Works
```

**Option 3: Wrap Existing Function**
```python
from ddtrace.llmobs import LLMObs

def existing_function():
    # Can't modify this function
    pass

# Wrap it
def traced_function():
    with LLMObs.workflow(name="existing_function"):
        return existing_function()
```

**Option 4: Conditional Tracing**
```python
from ddtrace.llmobs import LLMObs

def process_data(data, enable_tracing=False):
    if enable_tracing:
        with LLMObs.workflow(name="process_data"):
            result = do_processing(data)
            LLMObs.annotate(input_data=data, output_data=result)
            return result
    else:
        return do_processing(data)
```

**Common Mistake:**
```python
# ❌ WRONG - No active span
def process():
    LLMObs.annotate(...)  # Error!

# ✅ CORRECT - Wrap in context manager
def process():
    with LLMObs.workflow(name="process"):
        LLMObs.annotate(...)  # Works!
```

### Issue: Auto-instrumentation Not Working

**Solution:**
```python
from ddtrace import patch

# Explicitly enable integrations
patch(openai=True, anthropic=True, langchain=True)
```

## Performance Impact

- **Overhead:** <5ms per trace
- **Memory:** Minimal (async submission)
- **Network:** Batched submissions
- **Sampling:** Configurable (default: 100%)

## Security

### PII Handling

```python
# Redact sensitive data
LLMObs.annotate(
    input_data="User SSN: [REDACTED]",
    metadata={"pii_redacted": True}
)
```

### API Key Security

```python
# Never log API keys
LLMObs.annotate(
    metadata={
        "api_key_used": "openai",  # Provider name only
        "key_last_4": api_key[-4:]  # Last 4 chars only
    }
)
```

## Examples

See `examples/` directory for:
- `simple_chatbot.py` - Basic chatbot with tracing
- `rag_application.py` - RAG with retrieval and generation
- `multi_agent.py` - Multi-agent system
- `streaming_response.py` - Streaming with tracing
- `evaluation_example.py` - Custom evaluations

## Resources

- **Datadog Docs:** https://docs.datadoghq.com/llm_observability/
- **Python SDK:** https://docs.datadoghq.com/llm_observability/setup/sdk/python/
- **GitHub Examples:** https://github.com/DataDog/llm-observability
- **Traces UI:** https://app.datadoghq.com/llm/traces

## Quick Reference

```python
# Setup
from ddtrace.llmobs import LLMObs
LLMObs.enable(ml_app="app", api_key="...", agentless_enabled=True)

# Decorators (creates active span automatically)
@workflow  # Top-level operation
@task      # Intermediate step
@llm       # LLM call
@agent     # Agent operation

# Annotate (MUST be inside decorated function or context manager)
@workflow
def my_function():
    LLMObs.annotate(
        input_data=...,
        output_data=...,
        metadata={...},
        metrics={...},
        tags={...}
    )

# Context manager (creates active span)
with LLMObs.workflow(name="..."):
    LLMObs.annotate(...)  # Works here
    # Your code

# Flush
LLMObs.flush()
```

**⚠️ Remember:** `LLMObs.annotate()` requires an active span. Always use decorators or context managers!

## Agent Workflow

When instrumenting Python LLM applications:

1. ✅ Install `ddtrace`
2. ✅ Enable LLMObs with API key
3. ✅ Add decorators to functions
4. ✅ Annotate with metadata
5. ✅ View traces in Datadog
6. ✅ Create dashboards and monitors

**This skill provides complete LLM observability for Python applications.**

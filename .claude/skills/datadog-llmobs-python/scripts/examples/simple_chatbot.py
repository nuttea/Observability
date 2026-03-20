#!/usr/bin/env python3
"""
Simple Chatbot with Datadog LLM Observability
Demonstrates basic workflow, task, and LLM tracing
"""

import os
from ddtrace.llmobs import LLMObs
from ddtrace.llmobs.decorators import workflow, task, llm
from openai import OpenAI

# Initialize LLMObs
LLMObs.enable(
    ml_app="simple-chatbot",
    api_key=os.environ.get("DD_API_KEY"),
    site=os.environ.get("DD_SITE", "datadoghq.com"),
    agentless_enabled=True,
)

# Initialize OpenAI client
client = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))

@task
def preprocess_input(user_input):
    """Clean and prepare user input"""
    cleaned = user_input.strip().lower()
    
    LLMObs.annotate(
        input_data=user_input,
        output_data=cleaned,
        metadata={"preprocessing": "lowercase_strip"}
    )
    
    return cleaned

@llm(model_name="gpt-3.5-turbo", model_provider="openai")
def generate_response(message):
    """Generate response using OpenAI"""
    response = client.chat.completions.create(
        model="gpt-3.5-turbo",
        messages=[
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": message}
        ],
        temperature=0.7,
        max_tokens=150
    )
    
    # Annotate with token usage
    LLMObs.annotate(
        input_data=message,
        output_data=response.choices[0].message.content,
        metrics={
            "input_tokens": response.usage.prompt_tokens,
            "output_tokens": response.usage.completion_tokens,
            "total_tokens": response.usage.total_tokens
        },
        metadata={
            "model": "gpt-3.5-turbo",
            "temperature": 0.7
        }
    )
    
    return response.choices[0].message.content

@workflow
def chat(user_input):
    """Main chatbot workflow"""
    # Preprocess
    cleaned_input = preprocess_input(user_input)
    
    # Generate response
    response = generate_response(cleaned_input)
    
    # Annotate workflow
    LLMObs.annotate(
        input_data=user_input,
        output_data=response,
        tags={"use_case": "chatbot"}
    )
    
    return response

if __name__ == "__main__":
    # Example usage
    user_message = "What is the weather like today?"
    
    print(f"User: {user_message}")
    response = chat(user_message)
    print(f"Bot: {response}")
    
    # Flush traces before exit
    LLMObs.flush()
    print("\n✓ Trace sent to Datadog")
    print("View at: https://app.datadoghq.com/llm/traces")

import base64
from http import HTTPStatus
import os
import uuid
import time
import gradio as gr
from gradio_client import utils as client_utils
import modelscope_studio.components.antd as antd
import modelscope_studio.components.antdx as antdx
import modelscope_studio.components.base as ms
import modelscope_studio.components.pro as pro
from config import DEFAULT_THEME, DEFAULT_SYS_PROMPT, save_history, get_text, user_config, bot_config, welcome_config, markdown_config, upload_config, api_key, base_url, MODEL, THINKING_MODEL, bucket
from ui_components.logo import Logo
from ui_components.thinking_button import ThinkingButton

from openai import OpenAI
import socket
import requests
import urllib3
from urllib3.util.retry import Retry
from requests.adapters import HTTPAdapter

# Disable SSL warnings for testing purposes
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Initialize OpenAI client with enhanced network configuration
client = None
if api_key:
    # Configuration de timeout pour la production
    timeout_config = (30, 300)  # (connect timeout, read timeout)
    
    try:
        client = OpenAI(
            api_key=api_key,
            base_url=base_url,
            timeout=timeout_config
        )
        print("✅ OpenAI client initialized with enhanced network configuration")
    except Exception as e:
        print(f"❌ Failed to initialize OpenAI client: {e}")
        print("Continuing with client=None - API calls will fail but app will run")
        client = None
else:
    print("Warning: API_KEY environment variable not set. The application will run but API calls will fail.")
    print("Please set the API_KEY environment variable to use the application properly.")
    print("For OpenRouter, you can get your API key from: https://openrouter.ai/")


def encode_file_to_base64(file_path):
    with open(file_path, "rb") as file:
        mime_type = client_utils.get_mimetype(file_path)
        bae64_data = base64.b64encode(file.read()).decode("utf-8")
        return f"data:{mime_type};base64,{bae64_data}"


def file_path_to_oss_url(file_path: str):
    """Upload file to OSS with enhanced error handling and port support"""
    if file_path.startswith("http"):
        return file_path
    
    # If bucket is not configured, return the original file path
    if not bucket:
        print("OSS bucket not configured, returning local file path")
        return file_path
        
    ext = file_path.split('.')[-1]
    object_name = f'studio-temp/Qwen3-VL-Demo/{uuid.uuid4()}.{ext}'
    try:
        # Configuration avec timeout étendu pour upload
        bucket.put_object_from_file(object_name, file_path, progress_callback=None)
        file_url = file_path
        
        # Génération d'URL avec signature
        file_url = bucket.sign_url('GET',
                                   object_name,
                                   60 * 60,  # 1 heure
                                   slash_safe=True)
        print(f"✅ File uploaded to OSS: {object_name}")
        return file_url
    except Exception as e:
        print(f"⚠️ Warning: Could not upload file to OSS: {e}")
        print("Continuing with local file path")
        return file_path

def test_network_connectivity():
    """Test de la connectivité réseau vers les services externes"""
    import json
    import requests
    from datetime import datetime
    
    results = {
        'timestamp': datetime.now().isoformat(),
        'status': 'healthy',
        'tests': {}
    }
    
    # Test DNS resolution
    try:
        import socket
        socket.gethostbyname('openrouter.ai')
        results['tests']['dns'] = 'OK'
    except Exception as e:
        results['tests']['dns'] = f'FAILED: {e}'
        results['status'] = 'degraded'
    
    # Test OpenRouter API connectivity
    try:
        response = requests.get('https://openrouter.ai/api/v1/models', timeout=10)
        results['tests']['openrouter'] = f'HTTP {response.status_code}'
    except Exception as e:
        results['tests']['openrouter'] = f'FAILED: {e}'
        results['status'] = 'degraded'
    
    # Test GitHub connectivity
    try:
        response = requests.get('https://api.github.com', timeout=10)
        results['tests']['github'] = f'HTTP {response.status_code}'
    except Exception as e:
        results['tests']['github'] = f'FAILED: {e}'
        results['status'] = 'degraded'
    
    # Test OSS endpoint if configured
    if bucket:
        try:
            # Test basique de connectivité OSS
            test_url = bucket.sign_url('GET', 'test', 60)
            results['tests']['oss'] = 'Config OK'
        except Exception as e:
            results['tests']['oss'] = f'FAILED: {e}'
            results['status'] = 'degraded'
    
    return results


def format_history(history, oss_cache, sys_prompt=None):
    messages = [{
        "role": "system",
        "content": DEFAULT_SYS_PROMPT,
    }]
    for item in history:
        if item["role"] == "user":
            files = []
            for file_path in item["content"][0]["content"]:
                if file_path.startswith("http"):
                    files.append({
                        "type": "image_url",
                        "image_url": {
                            "url": file_path
                        }
                    })
                elif os.path.exists(file_path):
                    file_url = oss_cache.get(file_path,
                                             file_path_to_oss_url(file_path))
                    oss_cache[file_path] = file_url

                    file_url = file_url if file_url.startswith(
                        "http") else encode_file_to_base64(file_path=file_path)

                    mime_type = client_utils.get_mimetype(file_path)
                    if mime_type.startswith("image"):
                        files.append({
                            "type": "image_url",
                            "image_url": {
                                "url": file_url
                            }
                        })
                    elif mime_type.startswith("video"):
                        files.append({
                            "type": "video_url",
                            "video_url": {
                                "url": file_url
                            }
                        })

            messages.append({
                "role":
                "user",
                "content":
                files + [{
                    "type": "text",
                    "text": item["content"][1]["content"]
                }]
            })
        elif item["role"] == "assistant":
            contents = [{
                "type": "text",
                "text": content["content"]
            } for content in item["content"] if content["type"] == "text"]
            messages.append({
                "role":
                "assistant",
                "content":
                contents[0]["text"] if len(contents) > 0 else ""
            })
    return messages


class Gradio_Events:

    @staticmethod
    def submit(state_value):

        history = state_value["conversation_contexts"][
            state_value["conversation_id"]]["history"]
        enable_thinking = state_value["conversation_contexts"][
            state_value["conversation_id"]]["enable_thinking"]
        messages = format_history(history, state_value["oss_cache"])
        model = THINKING_MODEL if enable_thinking else MODEL
        history.append({
            "role": "assistant",
            "content": [],
            "key": str(uuid.uuid4()),
            "loading": True,
            "header": "Qwen3-VL",
            "status": "pending"
        })

        yield {
            chatbot: gr.update(value=history),
            state: gr.update(value=state_value),
        }
        try:
            if not client:
                history[-1]["loading"] = False
                history[-1]["status"] = "done"
                history[-1]["content"] += [{
                    "type":
                    "text",
                    "content":
                    '<span style="color: var(--color-red-500)">API not configured. Please set API_KEY environment variable.</span>'
                }]
                yield {
                    chatbot: gr.update(value=history),
                    state: gr.update(value=state_value)
                }
                return

            response = client.chat.completions.create(
                model=model,
                messages=messages,
                stream=True,
                extra_headers={
                    "HTTP-Referer": "https://qwen3-vl-demo.com",
                    "X-Title": "Qwen3-VL Demo",
                }
            )
            start_time = time.time()
            reasoning_content = ""
            answer_content = ""
            is_thinking = False
            is_answering = False
            contents = [None, None]
            for chunk in response:
                if not chunk or (
                        not chunk.choices[0].delta.content and
                    (not hasattr(chunk.choices[0].delta, "reasoning_content")
                     or not chunk.choices[0].delta.reasoning_content)):
                    pass
                else:
                    delta = chunk.choices[0].delta
                    if hasattr(
                            delta,
                            'reasoning_content') and delta.reasoning_content:
                        if not is_thinking:
                            contents[0] = {
                                "type": "tool",
                                "content": "",
                                "options": {
                                    "title": get_text("Thinking...", "思考中..."),
                                    "status": "pending"
                                },
                                "copyable": False,
                                "editable": False
                            }
                            is_thinking = True
                        reasoning_content += delta.reasoning_content
                    if hasattr(delta, 'content') and delta.content:
                        if not is_answering:
                            thought_cost_time = "{:.2f}".format(time.time() -
                                                                start_time)
                            if contents[0]:
                                contents[0]["options"]["title"] = get_text(
                                    f"End of Thought ({thought_cost_time}s)",
                                    f"已深度思考 (用时{thought_cost_time}s)")
                                contents[0]["options"]["status"] = "done"
                            contents[1] = {
                                "type": "text",
                                "content": "",
                            }

                            is_answering = True
                        answer_content += delta.content

                    if contents[0]:
                        contents[0]["content"] = reasoning_content
                    if contents[1]:
                        contents[1]["content"] = answer_content
                history[-1]["content"] = [
                    content for content in contents if content
                ]

                history[-1]["loading"] = False
                yield {
                    chatbot: gr.update(value=history),
                    state: gr.update(value=state_value)
                }
            print("model: ", model, "-", "reasoning_content: ",
                  reasoning_content, "\n", "content: ", answer_content)
            history[-1]["status"] = "done"
            cost_time = "{:.2f}".format(time.time() - start_time)
            history[-1]["footer"] = get_text(f"{cost_time}s",
                                             f"用时{cost_time}s")
            yield {
                chatbot: gr.update(value=history),
                state: gr.update(value=state_value),
            }
        except Exception as e:
            print("model: ", model, "-", "Error: ", e)
            history[-1]["loading"] = False
            history[-1]["status"] = "done"
            history[-1]["content"] += [{
                "type":
                "text",
                "content":
                f'<span style="color: var(--color-red-500)">{str(e)}</span>'
            }]
            yield {
                chatbot: gr.update(value=history),
                state: gr.update(value=state_value)
            }
            raise e

    @staticmethod
    def add_message(input_value, thinking_btn_state_value, state_value):
        text = input_value["text"]
        files = input_value["files"]
        if not state_value["conversation_id"]:
            random_id = str(uuid.uuid4())
            history = []
            state_value["conversation_id"] = random_id
            state_value["conversation_contexts"][
                state_value["conversation_id"]] = {
                    "history": history
                }
            state_value["conversations"].append({
                "label": text,
                "key": random_id
            })

        history = state_value["conversation_contexts"][
            state_value["conversation_id"]]["history"]

        state_value["conversation_contexts"][
            state_value["conversation_id"]] = {
                "history": history,
                "enable_thinking": thinking_btn_state_value["enable_thinking"]
            }

        history.append({
            "key":
            str(uuid.uuid4()),
            "role":
            "user",
            "content": [{
                "type": "file",
                "content": [f for f in files]
            }, {
                "type": "text",
                "content": text
            }]
        })
        yield Gradio_Events.preprocess_submit(clear_input=True)(state_value)

        try:
            for chunk in Gradio_Events.submit(state_value):
                yield chunk
        except Exception as e:
            raise e
        finally:
            yield Gradio_Events.postprocess_submit(state_value)

    @staticmethod
    def preprocess_submit(clear_input=True):

        def preprocess_submit_handler(state_value):
            history = state_value["conversation_contexts"][
                state_value["conversation_id"]]["history"]
            return {
                **({
                    input:
                    gr.update(value=None, loading=True) if clear_input else gr.update(loading=True),
                } if clear_input else {}),
                conversations:
                gr.update(active_key=state_value["conversation_id"],
                          items=list(
                              map(
                                  lambda item: {
                                      **item,
                                      "disabled":
                                      True if item["key"] != state_value[
                                          "conversation_id"] else False,
                                  }, state_value["conversations"]))),
                add_conversation_btn:
                gr.update(disabled=True),
                clear_btn:
                gr.update(disabled=True),
                conversation_delete_menu_item:
                gr.update(disabled=True),
                chatbot:
                gr.update(value=history,
                          bot_config=bot_config(
                              disabled_actions=['edit', 'retry', 'delete']),
                          user_config=user_config(
                              disabled_actions=['edit', 'delete'])),
                state:
                gr.update(value=state_value),
            }

        return preprocess_submit_handler

    @staticmethod
    def postprocess_submit(state_value):
        history = state_value["conversation_contexts"][
            state_value["conversation_id"]]["history"]
        return {
            input:
            gr.update(loading=False),
            conversation_delete_menu_item:
            gr.update(disabled=False),
            clear_btn:
            gr.update(disabled=False),
            conversations:
            gr.update(items=state_value["conversations"]),
            add_conversation_btn:
            gr.update(disabled=False),
            chatbot:
            gr.update(value=history,
                      bot_config=bot_config(),
                      user_config=user_config()),
            state:
            gr.update(value=state_value),
        }

    @staticmethod
    def cancel(state_value):
        history = state_value["conversation_contexts"][
            state_value["conversation_id"]]["history"]
        history[-1]["loading"] = False
        history[-1]["status"] = "done"
        history[-1]["footer"] = get_text("Chat completion paused", "对话已暂停")
        return Gradio_Events.postprocess_submit(state_value)

    @staticmethod
    def delete_message(state_value, e: gr.EventData):
        index = e._data["payload"][0]["index"]
        history = state_value["conversation_contexts"][
            state_value["conversation_id"]]["history"]
        history = history[:index] + history[index + 1:]

        state_value["conversation_contexts"][
            state_value["conversation_id"]]["history"] = history

        return gr.update(value=state_value)

    @staticmethod
    def edit_message(state_value, chatbot_value, e: gr.EventData):
        index = e._data["payload"][0]["index"]
        history = state_value["conversation_contexts"][
            state_value["conversation_id"]]["history"]
        history[index]["content"] = chatbot_value[index]["content"]
        if not history[index].get("edited"):
            history[index]["edited"] = True
            history[index]["footer"] = ((history[index]["footer"]) +
                                        " " if history[index].get("footer")
                                        else "") + get_text("Edited", "已编辑")
        return gr.update(value=state_value), gr.update(value=history)

    @staticmethod
    def regenerate_message(thinking_btn_state_value, state_value,
                           e: gr.EventData):
        index = e._data["payload"][0]["index"]
        history = state_value["conversation_contexts"][
            state_value["conversation_id"]]["history"]
        history = history[:index]

        state_value["conversation_contexts"][
            state_value["conversation_id"]] = {
                "history": history,
                "enable_thinking": thinking_btn_state_value["enable_thinking"]
            }

        yield Gradio_Events.preprocess_submit()(state_value)
        try:
            for chunk in Gradio_Events.submit(state_value):
                yield chunk
        except Exception as e:
            raise e
        finally:
            yield Gradio_Events.postprocess_submit(state_value)

    @staticmethod
    def apply_prompt(e: gr.EventData, input_value):
        input_value["text"] = e._data["payload"][0]["value"]["description"]
        input_value["files"] = e._data["payload"][0]["value"]["urls"]
        return gr.update(value=input_value)

    @staticmethod
    def new_chat(thinking_btn_state, state_value):
        if not state_value["conversation_id"]:
            return gr.skip()
        state_value["conversation_id"] = ""
        thinking_btn_state["enable_thinking"] = True
        return gr.update(active_key=state_value["conversation_id"]), gr.update(
            value=None), gr.update(value=thinking_btn_state), gr.update(
                value=state_value)

    @staticmethod
    def select_conversation(thinking_btn_state_value, state_value,
                            e: gr.EventData):
        active_key = e._data["payload"][0]
        if state_value["conversation_id"] == active_key or (
                active_key not in state_value["conversation_contexts"]):
            return gr.skip()
        state_value["conversation_id"] = active_key
        thinking_btn_state_value["enable_thinking"] = state_value[
            "conversation_contexts"][active_key]["enable_thinking"]
        return gr.update(active_key=active_key), gr.update(
            value=state_value["conversation_contexts"][active_key]
            ["history"]), gr.update(value=thinking_btn_state_value), gr.update(
                value=state_value)

    @staticmethod
    def click_conversation_menu(state_value, e: gr.EventData):
        conversation_id = e._data["payload"][0]["key"]
        operation = e._data["payload"][1]["key"]
        if operation == "delete":
            del state_value["conversation_contexts"][conversation_id]

            state_value["conversations"] = [
                item for item in state_value["conversations"]
                if item["key"] != conversation_id
            ]

            if state_value["conversation_id"] == conversation_id:
                state_value["conversation_id"] = ""
                return gr.update(
                    items=state_value["conversations"],
                    active_key=state_value["conversation_id"]), gr.update(
                        value=None), gr.update(value=state_value)
            else:
                return gr.update(
                    items=state_value["conversations"]), gr.skip(), gr.update(
                        value=state_value)
        return gr.skip()

    @staticmethod
    def clear_conversation_history(state_value):
        if not state_value["conversation_id"]:
            return gr.skip()
        state_value["conversation_contexts"][
            state_value["conversation_id"]]["history"] = []
        return gr.update(value=None), gr.update(value=state_value)

    @staticmethod
    def update_browser_state(state_value):

        return gr.update(value=dict(
            conversations=state_value["conversations"],
            conversation_contexts=state_value["conversation_contexts"]))

    @staticmethod
    def apply_browser_state(browser_state_value, state_value):
        state_value["conversations"] = browser_state_value["conversations"]
        state_value["conversation_contexts"] = browser_state_value[
            "conversation_contexts"]
        return gr.update(
            items=browser_state_value["conversations"]), gr.update(
                value=state_value)

    @staticmethod
    def update_voice_state(voice_state, language):
        """Update voice recording state"""
        return gr.update(value={"recording": voice_state, "language": language})


# JavaScript Web Speech API Implementation
javascript_web_speech = """
// Web Speech API Implementation for Voice Input
let recognition;
let isRecording = false;

function initializeSpeechRecognition() {
    if (!('webkitSpeechRecognition' in window) && !('SpeechRecognition' in window)) {
        console.warn('Web Speech API not supported in this browser');
        return null;
    }
    
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    recognition = new SpeechRecognition();
    recognition.continuous = true;
    recognition.interimResults = true;
    recognition.lang = 'en-US';
    
    return recognition;
}

function startVoiceRecognition() {
    if (!recognition) {
        recognition = initializeSpeechRecognition();
    }
    
    if (!recognition) {
        alert('Speech recognition is not supported in your browser. Please use Chrome or Edge.');
        return;
    }
    
    const inputElement = document.querySelector('input[placeholder*="help"]') || 
                        document.querySelector('input[type="text"]') ||
                        document.querySelector('textarea');
    
    if (!inputElement) {
        console.error('Input element not found');
        return;
    }
    
    recognition.onstart = function() {
        isRecording = true;
        updateVoiceButton(true);
        console.log('Voice recognition started');
    };
    
    recognition.onresult = function(event) {
        let finalTranscript = '';
        let interimTranscript = '';
        
        for (let i = event.resultIndex; i < event.results.length; i++) {
            const transcript = event.results[i][0].transcript;
            if (event.results[i].isFinal) {
                finalTranscript += transcript;
            } else {
                interimTranscript += transcript;
            }
        }
        
        // Update input with final transcript
        if (finalTranscript) {
            inputElement.value = finalTranscript;
            inputElement.dispatchEvent(new Event('input', { bubbles: true }));
        }
    };
    
    recognition.onerror = function(event) {
        console.error('Speech recognition error:', event.error);
        isRecording = false;
        updateVoiceButton(false);
        
        if (event.error === 'not-allowed') {
            alert('Microphone access denied. Please allow microphone access and try again.');
        } else if (event.error === 'no-speech') {
            alert('No speech detected. Please try again.');
        }
    };
    
    recognition.onend = function() {
        isRecording = false;
        updateVoiceButton(false);
        console.log('Voice recognition ended');
    };
    
    recognition.start();
}

function stopVoiceRecognition() {
    if (recognition) {
        recognition.stop();
    }
    isRecording = false;
    updateVoiceButton(false);
}

function toggleVoiceRecognition() {
    if (isRecording) {
        stopVoiceRecognition();
    } else {
        startVoiceRecognition();
    }
}

function updateVoiceButton(recording) {
    const voiceButton = document.querySelector('[data-testid="voice-btn"]') || 
                       document.querySelector('button[aria-label*="Audio"]') ||
                       document.querySelector('button[data-testid*="voice"]') ||
                       // Fallback to find button near the input
                       document.querySelector('input[placeholder*="help"]')?.parentNode.querySelector('button');
    
    if (voiceButton) {
        if (recording) {
            voiceButton.style.color = '#ff4d4f';
            voiceButton.style.background = 'rgba(255, 77, 79, 0.1)';
        } else {
            voiceButton.style.color = '';
            voiceButton.style.background = '';
        }
    }
}

function setLanguage(language) {
    if (recognition) {
        recognition.lang = language;
    }
}

// Initialize when page loads
document.addEventListener('DOMContentLoaded', function() {
    initializeSpeechRecognition();
    
    // Add click listeners to voice button and language select
    setTimeout(() => {
        const voiceButton = document.querySelector('button[aria-label*="Audio"]') ||
                           document.querySelector('button[title*="Audio"]') ||
                           // Find button with audio icon
                           Array.from(document.querySelectorAll('button')).find(btn => 
                               btn.querySelector('svg') && 
                               btn.querySelector('svg').getAttribute('aria-label') === 'AudioOutlined'
                           );
        
        const languageSelect = document.querySelector('select') ||
                              // Find select with language options
                              Array.from(document.querySelectorAll('select')).find(select => 
                                  select.querySelector('option[value="en-US"]')
                              );
        
        if (voiceButton) {
            voiceButton.addEventListener('click', toggleVoiceRecognition);
            voiceButton.setAttribute('data-testid', 'voice-btn');
        }
        
        if (languageSelect) {
            languageSelect.addEventListener('change', (e) => {
                setLanguage(e.target.value);
            });
        }
    }, 1000);
});
"""

css = """
.gradleio-container {
  padding: 0 !important;
}

.gradleio-container > main.fillable {
  padding: 0 !important;
}

#chatbot {
  height: calc(100vh - 21px - 16px);
  max-height: 1500px;
}

#chatbot .chatbot-conversations {
  height: 100vh;
  background-color: var(--ms-gr-ant-color-bg-layout);
  padding-left: 4px;
  padding-right: 4px;
}

#chatbot .chatbot-conversations .chatbot-conversations-list {
  padding-left: 0;
  padding-right: 0;
}

#chatbot .chatbot-chat {
  padding: 32px;
  padding-bottom: 0;
  height: 100%;
}

@media (max-width: 768px) {
  #chatbot .chatbot-chat {
      padding: 10px;
  }
}

#chatbot .chatbot-chat .chatbot-chat-messages {
  flex: 1;
}

/* Voice input controls styling */
.ms-voice-controls {
  max-width: 200px;
  display: inline-flex;
}

.ms-voice-controls .ant-select {
  width: 120px;
}
"""

# Add JavaScript to the interface
html_component = gr.HTML(javascript_web_speech)

with gr.Blocks(css=css, fill_width=True) as demo:
    # Voice state for recording management
    voice_state = gr.State({
        "recording": False,
        "language": "en-US"
    })
    
    state = gr.State({
        "conversation_contexts": {},
        "conversations": [],
        "conversation_id": "",
        "oss_cache": {}
    })

    with ms.Application(), antdx.XProvider(
            theme=DEFAULT_THEME), ms.AutoLoading():
        with antd.Row(gutter=[20, 20], wrap=False, elem_id="chatbot"):
            # Left Column
            with antd.Col(md=dict(flex="0 0 260px", span=24, order=0),
                          span=0,
                          order=1,
                          elem_style=dict(width=0)):
                with ms.Div(elem_classes="chatbot-conversations"):
                    with antd.Flex(vertical=True,
                                   gap="small",
                                   elem_style=dict(height="100%")):
                        # Logo
                        Logo()

                        # New Conversation Button
                        with antd.Button(value=None,
                                         color="primary",
                                         variant="filled",
                                         block=True) as add_conversation_btn:
                            ms.Text(get_text("New Conversation", "新建对话"))
                            with ms.Slot("icon"):
                                antd.Icon("PlusOutlined")

                        # Conversations List
                        with antdx.Conversations(
                                elem_classes="chatbot-conversations-list",
                        ) as conversations:
                            with ms.Slot('menu.items'):
                                with antd.Menu.Item(
                                        label="Delete", key="delete",
                                        danger=True
                                ) as conversation_delete_menu_item:
                                    with ms.Slot("icon"):
                                        antd.Icon("DeleteOutlined")
            # Right Column
            with antd.Col(flex=1, elem_style=dict(height="100%")):
                with antd.Flex(vertical=True,
                               gap="small",
                               elem_classes="chatbot-chat"):
                    # Chatbot
                    chatbot = pro.Chatbot(elem_classes="chatbot-chat-messages",
                                          height=0,
                                          markdown_config=markdown_config(),
                                          welcome_config=welcome_config(),
                                          user_config=user_config(),
                                          bot_config=bot_config())

                    # Input
                    with pro.MultimodalInput(
                            placeholder=get_text("How can I help you today?",
                                                 "有什么我能帮助您的吗？"),
                            upload_config=upload_config()) as input:
                        with ms.Slot("prefix"):
                            with antd.Flex(gap=4,
                                           wrap=True,
                                           elem_style=dict(
                                               maxWidth='40vw',
                                               display="inline-flex")):
                                with antd.Button(value=None,
                                                 type="text") as clear_btn:
                                    with ms.Slot("icon"):
                                        antd.Icon("ClearOutlined")
                                thinking_btn_state = ThinkingButton()
                                   
                        # Voice Input Controls
                        with antd.Flex(gap=4, wrap=True, elem_classes="ms-voice-controls"):
                            with antd.Select(
                                value="en-US",
                                options=[
                                    {"label": "🇺🇸 English", "value": "en-US"},
                                    {"label": "🇫🇷 Français", "value": "fr-FR"}
                                ]
                            ) as language_select:
                                pass
                            
                            with antd.Button(
                                value=None,
                                type="text",
                                size="small"
                            ) as voice_btn:
                                with ms.Slot("icon"):
                                    antd.Icon("AudioOutlined")

    # Events Handler
    # Browser State Handler
    if save_history:
        browser_state = gr.BrowserState(
            {
                "conversation_contexts": {},
                "conversations": [],
            },
            storage_key="qwen3_vl_demo_storage")
        state.change(fn=Gradio_Events.update_browser_state,
                     inputs=[state],
                     outputs=[browser_state])

        demo.load(fn=Gradio_Events.apply_browser_state,
                  inputs=[browser_state, state],
                  outputs=[conversations, state])

    # Conversations Handler
    add_conversation_btn.click(
        fn=Gradio_Events.new_chat,
        inputs=[thinking_btn_state, state],
        outputs=[conversations, chatbot, thinking_btn_state, state])
    conversations.active_change(
        fn=Gradio_Events.select_conversation,
        inputs=[thinking_btn_state, state],
        outputs=[conversations, chatbot, thinking_btn_state, state])
    conversations.menu_click(fn=Gradio_Events.click_conversation_menu,
                             inputs=[state],
                             outputs=[conversations, chatbot, state])
    # Chatbot Handler
    chatbot.welcome_prompt_select(fn=Gradio_Events.apply_prompt,
                                  inputs=[input],
                                  outputs=[input])

    chatbot.delete(fn=Gradio_Events.delete_message,
                   inputs=[state],
                   outputs=[state])
    chatbot.edit(fn=Gradio_Events.edit_message,
                 inputs=[state, chatbot],
                 outputs=[state, chatbot])

    regenerating_event = chatbot.retry(fn=Gradio_Events.regenerate_message,
                                       inputs=[thinking_btn_state, state],
                                       outputs=[
                                           input, clear_btn,
                                           conversation_delete_menu_item,
                                           add_conversation_btn, conversations,
                                           chatbot, state
                                       ])

    # Input Handler
    submit_event = input.submit(fn=Gradio_Events.add_message,
                                inputs=[input, thinking_btn_state, state],
                                outputs=[
                                    input, clear_btn,
                                    conversation_delete_menu_item,
                                    add_conversation_btn, conversations,
                                    chatbot, state
                                ])
    input.cancel(fn=Gradio_Events.cancel,
                 inputs=[state],
                 outputs=[
                     input, conversation_delete_menu_item, clear_btn,
                     conversations, add_conversation_btn, chatbot, state
                 ],
                 cancels=[submit_event, regenerating_event],
                 queue=False)

    clear_btn.click(fn=Gradio_Events.clear_conversation_history,
                    inputs=[state],
                    outputs=[chatbot, state])
    
    # Voice Input Event Handlers
    language_select.change(
        fn=Gradio_Events.update_voice_state,
        inputs=[voice_state, language_select],
        outputs=[voice_state]
    )

    voice_btn.click(
        fn=Gradio_Events.update_voice_state,
        inputs=[voice_state, language_select],
        outputs=[voice_state]
    )

# Function for health check - will be added as a component
def create_health_check():
    """Create a health check interface component"""
    def health_status():
        import json
        from datetime import datetime
        
        # Test de la connectivité réseau
        try:
            connectivity = test_network_connectivity()
            status = {
                "status": "healthy",
                "timestamp": connectivity['timestamp'],
                "connectivity": connectivity['tests'],
                "service": "Qwen3-VL Demo",
                "version": "1.0.0"
            }
            
            if connectivity['status'] == 'degraded':
                status["status"] = "degraded"
            
            return gr.JSON(status)
        except Exception as e:
            return gr.JSON({
                "status": "unhealthy",
                "error": str(e),
                "timestamp": datetime.now().isoformat()
            })
    
    return health_status

# Simple health check function for production
def simple_health_check():
    """Simple health check that always returns OK"""
    return {"status": "healthy", "service": "Qwen3-VL Demo", "version": "1.0.0"}

if __name__ == "__main__":
    print("🚀 Démarrage de Qwen3-VL Demo")
    
    # Configuration par défaut
    port = int(os.environ.get("PORT", 7860))
    host = "0.0.0.0"
    share = False
    debug = os.environ.get("DEBUG", "false").lower() == "true"
    
    print(f"🌐 Host: {host}")
    print(f"🔌 Port: {port}")
    print(f"🐛 Debug: {debug}")
    
    # Test de connectivité simple
    try:
        connectivity = test_network_connectivity()
        print(f"✅ Connectivité: {connectivity['status']}")
    except Exception as e:
        print(f"⚠️ Erreur test connectivité: {e}")
    
    # Configuration queue
    demo.queue(
        default_concurrency_limit=50,
        max_size=100
    ).launch(
        server_name=host,
        server_port=port,
        share=share,
        show_error=debug,
        quiet=not debug,
        ssr_mode=False,
        max_threads=50
    )
    
    print(f"✅ Application démarrée sur http://{host}:{port}")
    print("🎯 Qwen3-VL Demo est prêt!")

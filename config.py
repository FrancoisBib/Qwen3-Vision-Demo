import os
from modelscope_studio.components.pro.chatbot import ChatbotActionConfig, ChatbotBotConfig, ChatbotUserConfig, ChatbotWelcomeConfig, ChatbotMarkdownConfig
from modelscope_studio.components.pro.multimodal_input import MultimodalInputUploadConfig
import oss2
from oss2.credentials import EnvironmentVariableCredentialsProvider

# Oss - Optional configuration
endpoint = os.getenv("OSS_ENDPOINT")
region = os.getenv("OSS_REGION")
bucket_name = os.getenv("OSS_BUCKET_NAME")

# Only create bucket if all required OSS variables are present
bucket = None
if endpoint and region and bucket_name:
    try:
        auth = oss2.ProviderAuthV4(EnvironmentVariableCredentialsProvider())
        bucket = oss2.Bucket(auth, endpoint, bucket_name, region=region)
    except Exception as e:
        print(f"Warning: Could not initialize OSS bucket: {e}")
        bucket = None

# Env
is_cn = os.getenv('MODELSCOPE_ENVIRONMENT') == 'studio'
api_key = os.getenv('API_KEY')
base_url = "https://openrouter.ai/api/v1"

# OpenRouter models
MODEL = "nvidia/nemotron-nano-12b-v2-vl:free"
THINKING_MODEL = "nvidia/nemotron-nano-12b-v2-vl:free"


def get_text(text: str, cn_text: str):
    if is_cn:
        return cn_text
    return text


# Save history in browser
save_history = True


# Chatbot Config
def markdown_config():
    return ChatbotMarkdownConfig()


def user_config(disabled_actions=None):
    return ChatbotUserConfig(
        class_names=dict(content="user-message-content"),
        actions=[
            "copy", "edit",
            ChatbotActionConfig(
                action="delete",
                popconfirm=dict(title=get_text("Delete the message", "删除消息"),
                                description=get_text(
                                    "Are you sure to delete this message?",
                                    "确认删除该消息？"),
                                okButtonProps=dict(danger=True)))
        ],
        disabled_actions=disabled_actions)


def bot_config(disabled_actions=None):
    return ChatbotBotConfig(actions=[
        "copy", "edit",
        ChatbotActionConfig(
            action="retry",
            popconfirm=dict(
                title=get_text("Regenerate the message", "重新生成消息"),
                description=get_text(
                    "Regenerate the message will also delete all subsequent messages.",
                    "重新生成消息会删除所有后续消息。"),
                okButtonProps=dict(danger=True))),
        ChatbotActionConfig(action="delete",
                            popconfirm=dict(
                                title=get_text("Delete the message", "删除消息"),
                                description=get_text(
                                    "Are you sure to delete this message?",
                                    "确认删除该消息？"),
                                okButtonProps=dict(danger=True)))
    ],
                            avatar="./assets/qwen.png",
                            disabled_actions=disabled_actions)


def welcome_config():
    return ChatbotWelcomeConfig(
        variant="borderless",
        icon="./assets/qwen.png",
        title=get_text("Hello, I'm Qwen3-VL", "你好，我是 Qwen3-VL"),
        description=get_text(
            "Enter text and upload images or videos to get started.",
            "输入文本并上传图片或视频，开始对话吧。"),
        prompts=dict(
            title=get_text("How can I help you today?", "有什么我能帮助您的吗?"),
            styles={
                "list": {
                    "width": '100%',
                },
                "item": {
                    "flex": 1,
                },
            },
            items=[{
                "label":
                get_text("🤔 Logic Reasoning", "🤔 逻辑推理"),
                "children": [{
                    "urls": [
                        "https://misc-assets.oss-cn-beijing.aliyuncs.com/Qwen/Qwen3-VL-Demo/r-1-1.png",
                        "https://misc-assets.oss-cn-beijing.aliyuncs.com/Qwen/Qwen3-VL-Demo/r-1-2.png",
                        "https://misc-assets.oss-cn-beijing.aliyuncs.com/Qwen/Qwen3-VL-Demo/r-1-3.png"
                    ],
                    "description":
                    get_text(
                        "Which one of these does the kitty seem to want to try first?",
                        "这只猫看起来要尝试先做什么？")
                }, {
                    "urls": [
                        "https://misc-assets.oss-cn-beijing.aliyuncs.com/Qwen/Qwen3-VL-Demo/r-2.png",
                    ],
                    "description":
                    get_text(
                        "In the circuit, the diodes are ideal and the voltage source is Vs = 4 sin(ωt) V. Find the value measured on the ammeter.",
                        "电路中的 diodes 是理想的，电压源为 Vs = 4 sin(ωt) V。求电流表测量的数值。")
                }, {
                    "urls": [
                        "https://misc-assets.oss-cn-beijing.aliyuncs.com/Qwen/Qwen3-VL-Demo/r-3.png"
                    ],
                    "description":
                    get_text(
                        "Which is the most popular Friday drink in Boston?\nAnswer the question using a single word or phrase.",
                        " Boston 的星期五饮料中最受欢迎的是什么？\n请用一个单词或短语回答该问题。")
                }]
            }, {
                "label":
                get_text("🔍 Analysis & Reasoning", "🔍 分析推理"),
                "children": [
                    {
                        "urls": [
                            "https://misc-assets.oss-cn-beijing.aliyuncs.com/Qwen/Qwen3-VL-Demo/c-1.png"
                        ],
                        "description":
                        get_text(
                            "Read this chart or table and explain what it shows.",
                            "阅读这个图表或表格并解释其显示的内容。")
                    },
                    {
                        "urls": [
                            "https://misc-assets.oss-cn-beijing.aliyuncs.com/Qwen/Qwen3-VL-Demo/c-2.png"
                        ],
                        "description":
                        get_text(
                            "From this report (or photo of a whiteboard), draw three conclusions.",
                            "从这个报告（或白板照片）中得出三个结论。")
                    },
                    {
                        "urls": [
                            "https://misc-assets.oss-cn-beijing.aliyuncs.com/Qwen/Qwen3-VL-Demo/c-3.png"
                        ],
                        "description":
                        get_text("Describe the process illustrated in this image step by step.",
                                 "逐步描述该图中所示的过程。")
                    },
                ]
            }]),
    )


def upload_config():
    return MultimodalInputUploadConfig(
        accept="image/*,video/*",
        placeholder={
            "inline": {
                "title":
                "Upload files",
                "description":
                "Click or drag files to this area to upload images or videos"
            },
            "drop": {
                "title": "Drop files here",
            }
        })


DEFAULT_SYS_PROMPT = "You are a helpful and harmless assistant."

DEFAULT_THEME = {
    "token": {
        "colorPrimary": "#6A57FF",
    }
}

---
title: Qwen3 VL Demo
emoji: 😻
colorFrom: yellow
colorTo: pink
sdk: gradio
sdk_version: 5.29.0
app_file: app.py
pinned: false
license: apache-2.0
---

# Qwen3-VL Demo

A powerful multimodal AI chat application built with Qwen3-VL (Vision Language) model. This demo showcases advanced reasoning capabilities with text, images, and video inputs.

## Features

- **Multimodal Input**: Support for text, images, and video uploads
- **Advanced Reasoning**: Powered by Qwen3-VL with thinking capabilities
- **Real-time Chat**: Streamed responses with loading indicators
- **Voice Input**: Web Speech API integration for voice commands
- **Multi-language Support**: English and Chinese language support
- **Conversation Management**: Save, edit, delete, and organize chat history
- **OSS Integration**: Optional Alibaba Cloud OSS for file storage

## Prerequisites

- Python 3.8 or higher
- Hugging Face account (for deployment)
- API key from [OpenRouter](https://openrouter.ai/) (required for functionality)

## Environment Variables

### Required
- `API_KEY`: Your OpenRouter API key (get it from https://openrouter.ai/)w

## Local Development

### 1. Clone the repository
```bash
git clone <repository-url>
cd Qwen3-VL-Demo
```

### 2. Install dependencies
```bash
pip install -r requirements.txt
```

### 3. Set environment variables
```bash
export API_KEY="your-openrouter-api-key"
```

### 4. Run locally
```bash
python app.py
```

The application will be available at `http://localhost:7860`


### Method 2: Create from Template

1. Use this space as a template
2. Fork the repository
3. Update the configuration in `README.md` if needed
4. Set your environment variables in the Space settings

## Configuration

### Models Configuration
The application uses OpenRouter models by default:
- `MODEL`: "nvidia/nemotron-nano-12b-v2-vl:free"
- `THINKING_MODEL`: "nvidia/nemotron-nano-12b-v2-vl:free"

You can modify the models in `config.py` if needed.

### File Upload Limits
- Supported formats: Images (JPEG, PNG, GIF, etc.) and videos
- Maximum file size depends on your deployment configuration
- Files are automatically processed and can be stored in OSS if configured

## Troubleshooting

### Common Issues

1. **API Key not working**
   - Ensure your OpenRouter API key is correctly set
   - Check if you have credits in your OpenRouter account
   - Verify the model is available in your region

2. **File upload fails**
   - Check if OSS is properly configured (if using)
   - Ensure file format is supported
   - Verify file size limits

3. **Application won't start**
   - Check if all dependencies are installed
   - Verify environment variables are set correctly
   - Check logs for specific error messages

### Logs
Logs are printed to the console. For production deployment, consider setting up proper logging.

## Development

### Project Structure
```
Qwen3-VL-Demo/
├── app.py                 # Main application file
├── config.py              # Configuration settings
├── requirements.txt       # Python dependencies
├── assets/               # Static assets
│   └── qwen.png          # Qwen logo
├── ui_components/        # Custom UI components
│   ├── logo.py           # Logo component
│   └── thinking_button.py # Thinking mode button
└── README.md             # This file
```

### Key Components

- **app.py**: Main Gradio application with chat interface
- **config.py**: Configuration for models, UI, and integrations
- **ui_components/**: Reusable UI components

### Adding Features

1. **New models**: Update the `MODEL` and `THINKING_MODEL` in `config.py`
2. **Custom UI**: Add components in `ui_components/`
3. **New features**: Extend the event handlers in `app.py`

## License

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.

## Support

- For issues and questions, please open an issue in the repository
- For Hugging Face Space specific issues, check the Space logs
- For OpenRouter API issues, refer to their [documentation](https://openrouter.ai/docs)

## Acknowledgments

- [Qwen](https://github.com/QwenLM) for the powerful vision language model
- [Gradio](https://gradio.app/) for the user interface framework
- [ModelScope Studio](https://modelscope.cn/studios/overview) for enhanced components

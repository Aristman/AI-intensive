@echo off
if not exist "assets" mkdir assets
echo # DeepSeek API Configuration> assets\.env
echo DEEPSEEK_API_KEY=your_deepseek_api_key_here>> assets\.env
echo DEEPSEEK_BASE_URL=https://api.deepseek.com>> assets\.env
echo.>> assets\.env
echo # YandexGPT API Configuration (optional)>> assets\.env
echo YANDEX_API_KEY=your_yandex_api_key_here>> assets\.env
echo YANDEX_FOLDER_ID=your_yandex_folder_id_here>> assets\.env
echo YANDEX_GPT_BASE_URL=https://llm.api.cloud.yandex.net>> assets\.env
echo.>> assets\.env
echo # App Settings>> assets\.env
echo DEFAULT_MODEL=deepseek-chat>> assets\.env
echo DEFAULT_SYSTEM_PROMPT=You are a helpful AI assistant.>> assets\.env
echo.>> assets\.env
echo # Environment setup complete. Please edit assets\.env file with your actual API keys.>> assets\.env
echo Environment file created at assets\.env. Please edit it with your actual API keys.

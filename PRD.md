## 需求
请实现一个 macOS menu-bar 语音输入法应用 (Swift, macOS 14+)，具体要求：

```
1. 按住 Fn 键录音，松开后将转录文字注入当前聚焦的输入框。弃用 Apple 本地识别，改用 `URLSessionWebSocketTask` 接入阿里云百炼 Qwen-Omni-Realtime API 进行流式转录。采用 Manual 模式，按住 Fn 持续发送音频帧(Base64 编码的 PCM 数据，事件为 `input_audio_buffer.append`)，松开发送 `input_audio_buffer.commit`。Fn 键通过 `CGEvent tap` 全局监听，需抑制 Fn 事件传递以防止触发 emoji 选择器。

2. 默认语言必须为简体中文(zh-CN)，确保开箱即用就能识别中文输入。同时在菜单栏提供语言切换选项(英语、简体中文、繁体中文、日语、韩语)。语言选择存储在 `UserDefaults` 中，并在建立 WebSocket 会话(`session.update`)时，通过 `instructions` 参数将该语言偏好告知模型。

3. 录音时在屏幕底部居中显示一个特别优雅精致的无边框胶囊状悬浮窗，不要有红绿灯和 titlebar。使用 `NSPanel` (`nonactivatingPanel`) + `NSVisualEffectView` (`.hudWindow` 材质)，高度足够(56px，圆角半径 28px)，包含：
   - 左侧 5 根竖条波形动画(44×32px)，必须由实时音频 RMS 电平驱动(不要用写死的假动画)，说话声音大波形就大、安静时波形就小。各竖条权重为 `[0.5, 0.8, 1.0, 0.75, 0.55]` 形成自然的中间高两侧低效果，平滑包络(attack 40%、release 15%)，每根竖条添加 ±4% 随机抖动增加有机感。波形要足够大，清晰可见。在 `AVAudioEngine` 的 Tap 回调中，同时计算 RMS 驱动动画和提取 PCM 转换 Base64 发送给 WebSocket。
   - 右侧文字标签(弹性宽度 160-500px)实时显示转录文本，监听 WebSocket 返回的增量文本事件(如 `response.audio_transcript.delta` 或 `response.text.delta`)进行实时更新，胶囊随文字变多而弹性变宽。
   - 入场弹簧动画(0.35s)、文字宽度平滑过渡(0.25s)、退场缩放动画(0.22s)

4. 文字注入使用剪贴板 + 模拟 Cmd+V 粘贴方式，注入前需检测当前输入法：如果是 CJK 输入法，先临时切换到 ASCII 输入源(ABC/US 键盘)再粘贴，粘贴完成后恢复原输入法，防止中文输入法拦截 Cmd+V。注入完成后恢复原剪贴板内容。

5. 利用 Qwen-Omni-Realtime 的端到端多模态能力直接实现高精度转写与纠错，特别是中英文混杂的情况。在 `session.update` 中配置 `modalities` 为仅文本 `['text']`(不需要语音返回)。System Prompt (`instructions`) 要求非常保守：准确将用户的语音转写为文字，只修复明显的语音识别错误(如中文谐音错误、英文技术术语被错误转为中文如「配森」→「python」、「杰森」→「JSON」)，绝对不要改写、润色或删除任何看起来正确的内容，绝对不要包含任何对话或解释。

6. 在菜单栏提供 Qwen-Omni Settings 入口。Settings 窗口包含 DashScope API Key 和 Model(默认 `qwen3.5-omni-plus-realtime`) 两个输入框，API Key 输入框要能完全清空，以及 Test 和 Save 按钮。松开 Fn 键后，等待服务端返回完整的结束事件(如 `response.done` 或 `response.audio_transcript.done`)后再注入最终文本。

7. 应用以 `LSUIElement` 模式运行(仅菜单栏图标，无 Dock 图标)。使用 Swift Package Manager 构建，提供 Makefile(build/run/install/clean)，构建产物为签名的 `.app` bundle。"
```

> 注：上述需求描述来自 yetong 大神的开源分享

## 模型调用
这是可供你调试的临时 API key：<REDACTED> ，调试时请使用模型 qwen3-omni-flash-realtime-2025-09-15

模型说明和调用示例，可参考阿里云官网：https://help.aliyun.com/zh/model-studio/realtime?userCode=okjhlpr5#4dbf1dc38dj77

以下是根据官方文档摘录的示例。

### 示例方式一： DashScope Python SDK

#### 准备运行环境

您的 Python 版本需要不低于 3.10。

首先根据您的操作系统安装 pyaudio。

```sh
# macOS
brew install portaudio && pip install pyaudio
```

安装完成后，通过 pip 安装依赖：

```sh
pip install websocket-client dashscope
```

#### 选择交互模式

1. VAD 模式（Voice Activity Detection，自动检测语音起止）

服务端自动判断用户何时开始与停止说话并作出回应。

新建一个 python 文件，命名为vad_dash.py，并将以下代码复制到文件中：

```py
# 依赖：dashscope >= 1.23.9，pyaudio
import os
import base64
import time
import pyaudio
from dashscope.audio.qwen_omni import MultiModality, AudioFormat,OmniRealtimeCallback,OmniRealtimeConversation
import dashscope

# 配置参数：地址、API Key、音色、模型、模型角色
# 指定地域，设为cn表示中国内地（北京），设为intl表示国际（新加坡）
region = 'cn'
base_domain = 'dashscope.aliyuncs.com' if region == 'cn' else 'dashscope-intl.aliyuncs.com'
url = f'wss://{base_domain}/api-ws/v1/realtime'
# 配置 API Key，若没有设置环境变量，请用 API Key 将下行替换为 dashscope.api_key = "sk-xxx"
dashscope.api_key = os.getenv('DASHSCOPE_API_KEY')
# 指定音色
voice = 'Ethan'
# 指定模型
model = 'qwen3.5-omni-plus-realtime'
# 指定模型角色
instructions = "你是个人助理小云，请用幽默风趣的方式回答用户的问题"
class SimpleCallback(OmniRealtimeCallback):
    def __init__(self, pya):
        self.pya = pya
        self.out = None
    def on_open(self):
        # 初始化音频输出流
        self.out = self.pya.open(
            format=pyaudio.paInt16,
            channels=1,
            rate=24000,
            output=True
        )
    def on_event(self, response):
        if response['type'] == 'response.audio.delta':
            # 播放音频
            self.out.write(base64.b64decode(response['delta']))
        elif response['type'] == 'conversation.item.input_audio_transcription.completed':
            # 打印转录文本
            print(f"[User] {response['transcript']}")
        elif response['type'] == 'response.audio_transcript.done':
            # 打印助手回复文本
            print(f"[LLM] {response['transcript']}")

# 1. 初始化音频设备
pya = pyaudio.PyAudio()
# 2. 创建回调函数和会话
callback = SimpleCallback(pya)
conv = OmniRealtimeConversation(model=model, callback=callback, url=url)
# 3. 建立连接并配置会话
conv.connect()
conv.update_session(output_modalities=[MultiModality.AUDIO, MultiModality.TEXT], voice=voice, instructions=instructions)
# 4. 初始化音频输入流
mic = pya.open(format=pyaudio.paInt16, channels=1, rate=16000, input=True)
# 5. 主循环处理音频输入
print("对话已开始，对着麦克风说话 (Ctrl+C 退出)...")
try:
    while True:
        audio_data = mic.read(3200, exception_on_overflow=False)
        conv.append_audio(base64.b64encode(audio_data).decode())
        time.sleep(0.01)
except KeyboardInterrupt:
    # 清理资源
    conv.close()
    mic.close()
    callback.out.close()
    pya.terminate()
    print("\n对话结束")
```

运行vad_dash.py，通过麦克风即可与 Qwen-Omni-Realtime 模型实时对话，系统会检测您的音频起始位置并自动发送到服务器，无需您手动发送。


2. Manual 模式（按下即说，松开即发送）

客户端控制语音起止。用户说话结束后，客户端需主动发送消息至服务端。

新建一个 python 文件，命名为manual_dash.py，并将以下代码复制进文件中：

```py
# 依赖：dashscope >= 1.23.9，pyaudio。
import os
import base64
import sys
import threading
import pyaudio
from dashscope.audio.qwen_omni import *
import dashscope

# 如果没有设置环境变量，请用您的 API Key 将下行替换为 dashscope.api_key = "sk-xxx"
dashscope.api_key = os.getenv('DASHSCOPE_API_KEY')
voice = 'Ethan'

class MyCallback(OmniRealtimeCallback):
    """最简回调：建立连接时初始化扬声器，事件中直接播放返回音频。"""
    def __init__(self, ctx):
        super().__init__()
        self.ctx = ctx

    def on_open(self) -> None:
        # 连接建立后初始化 PyAudio 与扬声器(24k/mono/16bit)
        print('connection opened')
        try:
            self.ctx['pya'] = pyaudio.PyAudio()
            self.ctx['out'] = self.ctx['pya'].open(
                format=pyaudio.paInt16,
                channels=1,
                rate=24000,
                output=True
            )
            print('audio output initialized')
        except Exception as e:
            print('[Error] audio init failed: {}'.format(e))

    def on_close(self, close_status_code, close_msg) -> None:
        print('connection closed with code: {}, msg: {}'.format(close_status_code, close_msg))
        sys.exit(0)

    def on_event(self, response: str) -> None:
        try:
            t = response['type']
            handlers = {
                'session.created': lambda r: print('start session: {}'.format(r['session']['id'])),
                'conversation.item.input_audio_transcription.completed': lambda r: print('question: {}'.format(r['transcript'])),
                'response.audio_transcript.delta': lambda r: print('llm text: {}'.format(r['delta'])),
                'response.audio.delta': self._play_audio,
                'response.done': self._response_done,
            }
            h = handlers.get(t)
            if h:
                h(response)
        except Exception as e:
            print('[Error] {}'.format(e))

    def _play_audio(self, response):
        # 直接解码base64并写入输出流进行播放
        if self.ctx['out'] is None:
            return
        try:
            data = base64.b64decode(response['delta'])
            self.ctx['out'].write(data)
        except Exception as e:
            print('[Error] audio playback failed: {}'.format(e))

    def _response_done(self, response):
        # 标记本轮对话完成，用于主循环等待
        if self.ctx['conv'] is not None:
            print('[Metric] response: {}, first text delay: {}, first audio delay: {}'.format(
                self.ctx['conv'].get_last_response_id(),
                self.ctx['conv'].get_last_first_text_delay(),
                self.ctx['conv'].get_last_first_audio_delay(),
            ))
        if self.ctx['resp_done'] is not None:
            self.ctx['resp_done'].set()

def shutdown_ctx(ctx):
    """安全释放音频与PyAudio资源。"""
    try:
        if ctx['out'] is not None:
            ctx['out'].close()
            ctx['out'] = None
    except Exception:
        pass
    try:
        if ctx['pya'] is not None:
            ctx['pya'].terminate()
            ctx['pya'] = None
    except Exception:
        pass


def record_until_enter(pya_inst: pyaudio.PyAudio, sample_rate=16000, chunk_size=3200):
    """按 Enter 停止录音，返回PCM字节。"""
    frames = []
    stop_evt = threading.Event()

    stream = pya_inst.open(
        format=pyaudio.paInt16,
        channels=1,
        rate=sample_rate,
        input=True,
        frames_per_buffer=chunk_size
    )

    def _reader():
        while not stop_evt.is_set():
            try:
                frames.append(stream.read(chunk_size, exception_on_overflow=False))
            except Exception:
                break

    t = threading.Thread(target=_reader, daemon=True)
    t.start()
    input()  # 用户再次按 Enter 停止录音
    stop_evt.set()
    t.join(timeout=1.0)
    try:
        stream.close()
    except Exception:
        pass
    return b''.join(frames)


if __name__  == '__main__':
    print('Initializing ...')
    # 运行时上下文：存放音频与会话句柄
    ctx = {'pya': None, 'out': None, 'conv': None, 'resp_done': threading.Event()}
    callback = MyCallback(ctx)
    conversation = OmniRealtimeConversation(
        model='qwen3.5-omni-plus-realtime',
        callback=callback,
        # 以下为北京地域url，若使用新加坡地域的模型，需将url替换为：wss://dashscope-intl.aliyuncs.com/api-ws/v1/realtime
        url="wss://dashscope.aliyuncs.com/api-ws/v1/realtime",
    )
    try:
        conversation.connect()
    except Exception as e:
        print('[Error] connect failed: {}'.format(e))
        sys.exit(1)

    ctx['conv'] = conversation
    # 会话配置：启用文本+音频输出（禁用服务端VAD，改为手动录音）
    conversation.update_session(
        output_modalities=[MultiModality.AUDIO, MultiModality.TEXT],
        voice=voice,
        enable_input_audio_transcription=True,
        # 对输入音频做语音转录的模型，仅支持gummy-realtime-v1
        input_audio_transcription_model='gummy-realtime-v1',
        enable_turn_detection=False,
        instructions="你是个人助理小云，请你准确且友好地解答用户的问题，始终以乐于助人的态度回应。"
    )

    try:
        turn = 1
        while True:
            print(f"\n--- 第 {turn} 轮对话 ---")
            print("按 Enter 开始录音（输入 q 回车退出）...")
            user_input = input()
            if user_input.strip().lower() in ['q', 'quit']:
                print("用户请求退出...")
                break
            print("录音中... 再次按 Enter 停止录音。")
            if ctx['pya'] is None:
                ctx['pya'] = pyaudio.PyAudio()
            recorded = record_until_enter(ctx['pya'])
            if not recorded:
                print("未录制到有效音频，请重试。")
                continue
            print(f"成功录制音频: {len(recorded)} 字节，发送中...")

            # 以3200字节为块发送（对应16k/16bit/100ms）
            chunk_size = 3200
            for i in range(0, len(recorded), chunk_size):
                chunk = recorded[i:i+chunk_size]
                conversation.append_audio(base64.b64encode(chunk).decode('ascii'))

            print("发送完成，等待模型响应...")
            ctx['resp_done'].clear()
            conversation.commit()
            conversation.create_response()
            ctx['resp_done'].wait()
            print('播放音频完成')
            turn += 1
    except KeyboardInterrupt:
        print("\n程序被用户中断")
    finally:
        shutdown_ctx(ctx)
        print("程序退出")
```

运行manual_dash.py，按 Enter 键开始说话，再按一次获取模型响应的音频。

### 示例方式二：WebSocket(Python)

#### 准备运行环境

您的 Python 版本需要不低于 3.10。

首先根据您的操作系统来安装 pyaudio。

```sh
# macOS
brew install portaudio && pip install pyaudio
```

安装完成后，通过 pip 安装 websocket 相关的依赖：

```sh
pip install websockets==15.0.1
```

#### 创建客户端

在本地新建一个 python 文件，命名为omni_realtime_client.py，并将以下代码复制进文件中：

```py
import asyncio
import websockets
import json
import base64
import time
from typing import Optional, Callable, List, Dict, Any
from enum import Enum

class TurnDetectionMode(Enum):
    SERVER_VAD = "server_vad"
    SEMANTIC_VAD = "semantic_vad"  # 使用qwen3.5-omni-realtime模型时推荐
    MANUAL = "manual"

class OmniRealtimeClient:

    def __init__(
            self,
            base_url,
            api_key: str,
            model: str = "",
            voice: str = "Ethan",
            instructions: str = "You are a helpful assistant.",
            turn_detection_mode: TurnDetectionMode = TurnDetectionMode.SERVER_VAD,
            on_text_delta: Optional[Callable[[str], None]] = None,
            on_audio_delta: Optional[Callable[[bytes], None]] = None,
            on_input_transcript: Optional[Callable[[str], None]] = None,
            on_output_transcript: Optional[Callable[[str], None]] = None,
            extra_event_handlers: Optional[Dict[str, Callable[[Dict[str, Any]], None]]] = None
    ):
        self.base_url = base_url
        self.api_key = api_key
        self.model = model
        self.voice = voice
        self.instructions = instructions
        self.ws = None
        self.on_text_delta = on_text_delta
        self.on_audio_delta = on_audio_delta
        self.on_input_transcript = on_input_transcript
        self.on_output_transcript = on_output_transcript
        self.turn_detection_mode = turn_detection_mode
        self.extra_event_handlers = extra_event_handlers or {}

        # 当前回复状态
        self._current_response_id = None
        self._current_item_id = None
        self._is_responding = False
        # 输入/输出转录打印状态
        self._print_input_transcript = True
        self._output_transcript_buffer = ""

    async def connect(self) -> None:
        """与 Realtime API 建立 WebSocket 连接。"""
        url = f"{self.base_url}?model={self.model}"
        headers = {
            "Authorization": f"Bearer {self.api_key}"
        }
        self.ws = await websockets.connect(url, additional_headers=headers)

        # 会话配置
        session_config = {
            "modalities": ["text", "audio"],
            "voice": self.voice,
            "instructions": self.instructions,
            "input_audio_format": "pcm",
            "output_audio_format": "pcm",
            "input_audio_transcription": {
                "model": "gummy-realtime-v1"
            }
        }

        if self.turn_detection_mode == TurnDetectionMode.MANUAL:
            session_config['turn_detection'] = None
            await self.update_session(session_config)
        elif self.turn_detection_mode == TurnDetectionMode.SERVER_VAD:
            session_config['turn_detection'] = {
                "type": "server_vad",
                "threshold": 0.1,
                "prefix_padding_ms": 500,
                "silence_duration_ms": 900
            }
            await self.update_session(session_config)
        elif self.turn_detection_mode == TurnDetectionMode.SEMANTIC_VAD:
            session_config['turn_detection'] = {
                "type": "semantic_vad",
                "threshold": 0.1,
                "prefix_padding_ms": 500,
                "silence_duration_ms": 900
            }
            await self.update_session(session_config)
        else:
            raise ValueError(f"Invalid turn detection mode: {self.turn_detection_mode}")

    async def send_event(self, event) -> None:
        event['event_id'] = "event_" + str(int(time.time() * 1000))
        await self.ws.send(json.dumps(event))

    async def update_session(self, config: Dict[str, Any]) -> None:
        """更新会话配置。"""
        event = {
            "type": "session.update",
            "session": config
        }
        await self.send_event(event)

    async def stream_audio(self, audio_chunk: bytes) -> None:
        """向 API 流式发送原始音频数据。"""
        # 仅支持 16bit 16kHz 单声道 PCM
        audio_b64 = base64.b64encode(audio_chunk).decode()
        append_event = {
            "type": "input_audio_buffer.append",
            "audio": audio_b64
        }
        await self.send_event(append_event)

    async def commit_audio_buffer(self) -> None:
        """提交音频缓冲区以触发处理。"""
        event = {
            "type": "input_audio_buffer.commit"
        }
        await self.send_event(event)

    async def append_image(self, image_chunk: bytes) -> None:
        """向图像缓冲区追加图像数据。
        图像数据可以来自本地文件，也可以来自实时视频流。
        注意:
            - 图像格式必须为 JPG 或 JPEG。推荐分辨率为 480P 或 720P，最高支持 1080P。
            - 单张图片大小不应超过 500KB。
            - 将图像数据编码为 Base64 后再发送。
            - 建议以 1张/秒 的频率向服务端发送图像。
            - 在发送图像数据之前，需要至少发送过一次音频数据。
        """
        image_b64 = base64.b64encode(image_chunk).decode()
        event = {
            "type": "input_image_buffer.append",
            "image": image_b64
        }
        await self.send_event(event)

    async def create_response(self) -> None:
        """向 API 请求生成回复（仅在手动模式下需要调用）。"""
        event = {
            "type": "response.create"
        }
        await self.send_event(event)

    async def cancel_response(self) -> None:
        """取消当前回复。"""
        event = {
            "type": "response.cancel"
        }
        await self.send_event(event)

    async def handle_interruption(self):
        """处理用户对当前回复的打断。"""
        if not self._is_responding:
            return
        # 1. 取消当前回复
        if self._current_response_id:
            await self.cancel_response()

        self._is_responding = False
        self._current_response_id = None
        self._current_item_id = None

    async def handle_messages(self) -> None:
        try:
            async for message in self.ws:
                event = json.loads(message)
                event_type = event.get("type")
                if event_type == "error":
                    print(" Error: ", event['error'])
                    continue
                elif event_type == "response.created":
                    self._current_response_id = event.get("response", {}).get("id")
                    self._is_responding = True
                elif event_type == "response.output_item.added":
                    self._current_item_id = event.get("item", {}).get("id")
                elif event_type == "response.done":
                    self._is_responding = False
                    self._current_response_id = None
                    self._current_item_id = None
                elif event_type == "input_audio_buffer.speech_started":
                    print("检测到语音开始")
                    if self._is_responding:
                        print("处理打断")
                        await self.handle_interruption()
                elif event_type == "input_audio_buffer.speech_stopped":
                    print("检测到语音结束")
                elif event_type == "response.text.delta":
                    if self.on_text_delta:
                        self.on_text_delta(event["delta"])
                elif event_type == "response.audio.delta":
                    if self.on_audio_delta:
                        audio_bytes = base64.b64decode(event["delta"])
                        self.on_audio_delta(audio_bytes)
                elif event_type == "conversation.item.input_audio_transcription.completed":
                    transcript = event.get("transcript", "")
                    print(f"用户: {transcript}")
                    if self.on_input_transcript:
                        await asyncio.to_thread(self.on_input_transcript, transcript)
                        self._print_input_transcript = True
                elif event_type == "response.audio_transcript.delta":
                    if self.on_output_transcript:
                        delta = event.get("delta", "")
                        if not self._print_input_transcript:
                            self._output_transcript_buffer += delta
                        else:
                            if self._output_transcript_buffer:
                                await asyncio.to_thread(self.on_output_transcript, self._output_transcript_buffer)
                                self._output_transcript_buffer = ""
                            await asyncio.to_thread(self.on_output_transcript, delta)
                elif event_type == "response.audio_transcript.done":
                    print(f"大模型: {event.get('transcript', '')}")
                    self._print_input_transcript = False
                elif event_type in self.extra_event_handlers:
                    self.extra_event_handlers[event_type](event)
        except websockets.exceptions.ConnectionClosed:
            print(" Connection closed")
        except Exception as e:
            print(" Error in message handling: ", str(e))
    async def close(self) -> None:
        """关闭 WebSocket 连接。"""
        if self.ws:
            await self.ws.close()
```

#### 选择交互模式

1. VAD 模式（Voice Activity Detection，自动检测语音起止）

Realtime API 自动判断用户何时开始与停止说话并作出回应。
在omni_realtime_client.py的同级目录下新建另一个 python 文件，命名为vad_mode.py，并将以下代码复制进文件中：

```py
# -- coding: utf-8 --
import os, asyncio, pyaudio, queue, threading
from omni_realtime_client import OmniRealtimeClient, TurnDetectionMode

# 音频播放器类（处理中断）
class AudioPlayer:
    def __init__(self, pyaudio_instance, rate=24000):
        self.stream = pyaudio_instance.open(format=pyaudio.paInt16, channels=1, rate=rate, output=True)
        self.queue = queue.Queue()
        self.stop_evt = threading.Event()
        self.interrupt_evt = threading.Event()
        threading.Thread(target=self._run, daemon=True).start()

    def _run(self):
        while not self.stop_evt.is_set():
            try:
                data = self.queue.get(timeout=0.5)
                if data is None: break
                if not self.interrupt_evt.is_set(): self.stream.write(data)
                self.queue.task_done()
            except queue.Empty: continue

    def add_audio(self, data): self.queue.put(data)
    def handle_interrupt(self): self.interrupt_evt.set(); self.queue.queue.clear()
    def stop(self): self.stop_evt.set(); self.queue.put(None); self.stream.stop_stream(); self.stream.close()

# 麦克风录音并发送
async def record_and_send(client):
    p = pyaudio.PyAudio()
    stream = p.open(format=pyaudio.paInt16, channels=1, rate=16000, input=True, frames_per_buffer=3200)
    print("开始录音，请讲话...")
    try:
        while True:
            audio_data = stream.read(3200)
            await client.stream_audio(audio_data)
            await asyncio.sleep(0.02)
    finally:
        stream.stop_stream(); stream.close(); p.terminate()

async def main():
    p = pyaudio.PyAudio()
    player = AudioPlayer(pyaudio_instance=p)

    client = OmniRealtimeClient(
        # 以下是中国内地（北京）地域 base_url，国际（新加坡）地域base_url为wss://dashscope-intl.aliyuncs.com/api-ws/v1/realtime
        base_url="wss://dashscope.aliyuncs.com/api-ws/v1/realtime",
        api_key=os.environ.get("DASHSCOPE_API_KEY"),
        model="qwen3.5-omni-plus-realtime",
        voice="Ethan",
        instructions="你是小云，风趣幽默的好助手",
        # 使用qwen3.5-omni-realtime模型时推荐设为SEMANTIC_VAD
        turn_detection_mode=TurnDetectionMode.SEMANTIC_VAD,
        on_text_delta=lambda t: print(f"\nAssistant: {t}", end="", flush=True),
        on_audio_delta=player.add_audio,
    )

    await client.connect()
    print("连接成功，开始实时对话...")

    # 并发运行
    await asyncio.gather(client.handle_messages(), record_and_send(client))

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n程序已退出。")
```

运行vad_mode.py，通过麦克风即可与 Realtime 模型实时对话，系统会检测您的音频起始位置并自动发送到服务器，无需您手动发送。


2. Manual 模式（按下即说，松开即发送）

客户端控制语音起止。用户说话结束后，客户端需主动发送消息至服务端。
在omni_realtime_client.py的同级目录下新建另一个 python 文件，命名为manual_mode.py，并将以下代码复制进文件中：

```py
# -- coding: utf-8 --
import os
import asyncio
import time
import threading
import queue
import pyaudio
from omni_realtime_client import OmniRealtimeClient, TurnDetectionMode

class AudioPlayer:
    """实时音频播放器类"""
    def __init__(self, sample_rate=24000, channels=1, sample_width=2):
        self.sample_rate = sample_rate
        self.channels = channels
        self.sample_width = sample_width  # 2 bytes for 16-bit
        self.audio_queue = queue.Queue()
        self.is_playing = False
        self.play_thread = None
        self.pyaudio_instance = None
        self.stream = None
        self._lock = threading.Lock()  # 添加锁来同步访问
        self._last_data_time = time.time()  # 记录最后接收数据的时间
        self._response_done = False  # 添加响应完成标志
        self._waiting_for_response = False # 标记是否正在等待服务器响应
        # 记录最后一次向音频流写入数据的时间及最近一次音频块的时长，用于更精确地判断播放结束
        self._last_play_time = time.time()
        self._last_chunk_duration = 0.0

    def start(self):
        """启动音频播放器"""
        with self._lock:
            if self.is_playing:
                return

            self.is_playing = True

            try:
                self.pyaudio_instance = pyaudio.PyAudio()

                # 创建音频输出流
                self.stream = self.pyaudio_instance.open(
                    format=pyaudio.paInt16,  # 16-bit
                    channels=self.channels,
                    rate=self.sample_rate,
                    output=True,
                    frames_per_buffer=1024
                )

                # 启动播放线程
                self.play_thread = threading.Thread(target=self._play_audio)
                self.play_thread.daemon = True
                self.play_thread.start()

                print("音频播放器已启动")
            except Exception as e:
                print(f"启动音频播放器失败: {e}")
                self._cleanup_resources()
                raise

    def stop(self):
        """停止音频播放器"""
        with self._lock:
            if not self.is_playing:
                return

            self.is_playing = False

        # 清空队列
        while not self.audio_queue.empty():
            try:
                self.audio_queue.get_nowait()
            except queue.Empty:
                break

        # 等待播放线程结束（在锁外面等待，避免死锁）
        if self.play_thread and self.play_thread.is_alive():
            self.play_thread.join(timeout=2.0)

        # 再次获取锁来清理资源
        with self._lock:
            self._cleanup_resources()

        print("音频播放器已停止")

    def _cleanup_resources(self):
        """清理音频资源（必须在锁内调用）"""
        try:
            # 关闭音频流
            if self.stream:
                if not self.stream.is_stopped():
                    self.stream.stop_stream()
                self.stream.close()
                self.stream = None
        except Exception as e:
            print(f"关闭音频流时出错: {e}")

        try:
            if self.pyaudio_instance:
                self.pyaudio_instance.terminate()
                self.pyaudio_instance = None
        except Exception as e:
            print(f"终止PyAudio时出错: {e}")

    def add_audio_data(self, audio_data):
        """添加音频数据到播放队列"""
        if self.is_playing and audio_data:
            self.audio_queue.put(audio_data)
            with self._lock:
                self._last_data_time = time.time()  # 更新最后接收数据的时间
                self._waiting_for_response = False # 收到数据，不再等待

    def stop_receiving_data(self):
        """标记不再接收新的音频数据"""
        with self._lock:
            self._response_done = True
            self._waiting_for_response = False # 响应结束，不再等待

    def prepare_for_next_turn(self):
        """为下一轮对话重置播放器状态。"""
        with self._lock:
            self._response_done = False
            self._last_data_time = time.time()
            self._last_play_time = time.time()
            self._last_chunk_duration = 0.0
            self._waiting_for_response = True # 开始等待下一轮响应

        # 清空上一轮可能残留的音频数据
        while not self.audio_queue.empty():
            try:
                self.audio_queue.get_nowait()
            except queue.Empty:
                break

    def is_finished_playing(self):
        """检查是否已经播放完所有音频数据"""
        with self._lock:
            queue_size = self.audio_queue.qsize()
            time_since_last_data = time.time() - self._last_data_time
            time_since_last_play = time.time() - self._last_play_time

            # ---------------------- 智能结束判定 ----------------------
            # 1. 首选：如果服务器已标记完成且播放队列为空
            #    进一步等待最近一块音频播放完毕（音频块时长 + 0.1s 容错）。
            if self._response_done and queue_size == 0:
                min_wait = max(self._last_chunk_duration + 0.1, 0.5)  # 至少等待 0.5s
                if time_since_last_play >= min_wait:
                    return True

            # 2. 备用：如果长时间没有新数据且播放队列为空
            #    当服务器没有明确发出 `response.done` 时，此逻辑作为保障
            if not self._waiting_for_response and queue_size == 0 and time_since_last_data > 1.0:
                print("\n(超时未收到新音频，判定播放结束)")
                return True

            return False

    def _play_audio(self):
        """播放音频数据的工作线程"""
        while True:
            # 检查是否应该停止
            with self._lock:
                if not self.is_playing:
                    break
                stream_ref = self.stream  # 获取流的引用

            try:
                # 从队列中获取音频数据，超时0.1秒
                audio_data = self.audio_queue.get(timeout=0.1)

                # 再次检查状态和流的有效性
                with self._lock:
                    if self.is_playing and stream_ref and not stream_ref.is_stopped():
                        try:
                            # 播放音频数据
                            stream_ref.write(audio_data)
                            # 更新最近播放信息
                            self._last_play_time = time.time()
                            self._last_chunk_duration = len(audio_data) / (self.channels * self.sample_width) / self.sample_rate
                        except Exception as e:
                            print(f"写入音频流时出错: {e}")
                            break

                # 标记该数据块已处理完成
                self.audio_queue.task_done()

            except queue.Empty:
                # 队列为空时继续等待
                continue
            except Exception as e:
                print(f"播放音频时出错: {e}")
                break

class MicrophoneRecorder:
    """实时麦克风录音器"""
    def __init__(self, sample_rate=16000, channels=1, chunk_size=3200):
        self.sample_rate = sample_rate
        self.channels = channels
        self.chunk_size = chunk_size
        self.pyaudio_instance = None
        self.stream = None
        self.frames = []
        self._is_recording = False
        self._record_thread = None

    def _recording_thread(self):
        """录音工作线程"""
        # 在 _is_recording 为 True 期间，持续从音频流中读取数据
        while self._is_recording:
            try:
                # 使用 exception_on_overflow=False 避免因缓冲区溢出而崩溃
                data = self.stream.read(self.chunk_size, exception_on_overflow=False)
                self.frames.append(data)
            except (IOError, OSError) as e:
                # 当流被关闭时，读取操作可能会引发错误
                print(f"录音流读取错误，可能已关闭: {e}")
                break

    def start(self):
        """开始录音"""
        if self._is_recording:
            print("录音已在进行中。")
            return

        self.frames = []
        self._is_recording = True

        try:
            self.pyaudio_instance = pyaudio.PyAudio()
            self.stream = self.pyaudio_instance.open(
                format=pyaudio.paInt16,
                channels=self.channels,
                rate=self.sample_rate,
                input=True,
                frames_per_buffer=self.chunk_size
            )

            self._record_thread = threading.Thread(target=self._recording_thread)
            self._record_thread.daemon = True
            self._record_thread.start()
            print("麦克风录音已开始...")
        except Exception as e:
            print(f"启动麦克风失败: {e}")
            self._is_recording = False
            self._cleanup()
            raise

    def stop(self):
        """停止录音并返回音频数据"""
        if not self._is_recording:
            return None

        self._is_recording = False

        # 等待录音线程安全退出
        if self._record_thread:
            self._record_thread.join(timeout=1.0)

        self._cleanup()

        print("麦克风录音已停止。")
        return b''.join(self.frames)

    def _cleanup(self):
        """安全地清理 PyAudio 资源"""
        if self.stream:
            try:
                if self.stream.is_active():
                    self.stream.stop_stream()
                self.stream.close()
            except Exception as e:
                print(f"关闭音频流时出错: {e}")

        if self.pyaudio_instance:
            try:
                self.pyaudio_instance.terminate()
            except Exception as e:
                print(f"终止 PyAudio 实例时出错: {e}")

        self.stream = None
        self.pyaudio_instance = None

async def interactive_test():
    """
    交互式测试脚本：允许多轮连续对话，每轮可以发送音频和图片。
    """
    # ------------------- 1. 初始化和连接 (一次性) -------------------
    api_key = os.environ.get("DASHSCOPE_API_KEY")
    if not api_key:
        print("请设置DASHSCOPE_API_KEY环境变量")
        return

    print("--- 实时多轮音视频对话客户端 ---")
    print("正在初始化音频播放器和客户端...")

    audio_player = AudioPlayer()
    audio_player.start()

    def on_audio_received(audio_data):
        audio_player.add_audio_data(audio_data)

    def on_response_done(event):
        print("\n(收到响应结束标记)")
        audio_player.stop_receiving_data()

    realtime_client = OmniRealtimeClient(
        base_url="wss://dashscope.aliyuncs.com/api-ws/v1/realtime",
        api_key=api_key,
        model="qwen3.5-omni-plus-realtime",
        voice="Ethan",
        instructions="你是个人助理小云，请你准确且友好地解答用户的问题，始终以乐于助人的态度回应。", # 设定模型角色
        on_text_delta=lambda text: print(f"助手回复: {text}", end="", flush=True),
        on_audio_delta=on_audio_received,
        turn_detection_mode=TurnDetectionMode.MANUAL,
        extra_event_handlers={"response.done": on_response_done}
    )

    message_handler_task = None
    try:
        await realtime_client.connect()
        print("已连接到服务器。输入 'q' 或 'quit' 可随时退出程序。")
        message_handler_task = asyncio.create_task(realtime_client.handle_messages())
        await asyncio.sleep(0.5)

        turn_counter = 1
        # ------------------- 2. 多轮对话循环 -------------------
        while True:
            print(f"\n--- 第 {turn_counter} 轮对话 ---")
            audio_player.prepare_for_next_turn()

            recorded_audio = None
            image_paths = []

            # --- 获取用户输入：从麦克风录音 ---
            loop = asyncio.get_event_loop()
            recorder = MicrophoneRecorder(sample_rate=16000) # 推荐使用16k采样率进行语音识别

            print("准备录音。按 Enter 键开始录音 (或输入 'q' 退出)...")
            user_input = await loop.run_in_executor(None, input)
            if user_input.strip().lower() in ['q', 'quit']:
                print("用户请求退出...")
                return

            try:
                recorder.start()
            except Exception:
                print("无法启动录音，请检查您的麦克风权限和设备。跳过本轮。")
                continue

            print("录音中... 再次按 Enter 键停止录音。")
            await loop.run_in_executor(None, input)

            recorded_audio = recorder.stop()

            if not recorded_audio or len(recorded_audio) == 0:
                print("未录制到有效音频，请重新开始本轮对话。")
                continue

            # --- 获取图片输入 (可选) ---
            # 以下图片输入功能已被注释，暂时禁用。若需启用请取消下方代码注释。
            # print("\n请逐行输入【图片文件】的绝对路径 (可选)。完成后，输入 's' 或按 Enter 发送请求。")
            # while True:
            #     path = input("图片路径: ").strip()
            #     if path.lower() == 's' or path == '':
            #         break
            #     if path.lower() in ['q', 'quit']:
            #         print("用户请求退出...")
            #         return
            #
            #     if not os.path.isabs(path):
            #         print("错误: 请输入绝对路径。")
            #         continue
            #     if not os.path.exists(path):
            #         print(f"错误: 文件不存在 -> {path}")
            #         continue
            #     image_paths.append(path)
            #     print(f"已添加图片: {os.path.basename(path)}")

            # --- 3. 发送数据并获取响应 ---
            print("\n--- 输入确认 ---")
            print(f"待处理音频: 1个 (来自麦克风), 图片: {len(image_paths)}个")
            print("------------------")

            # 3.1 发送录制的音频
            try:
                print(f"发送麦克风录音 ({len(recorded_audio)}字节)")
                await realtime_client.stream_audio(recorded_audio)
                await asyncio.sleep(0.1)
            except Exception as e:
                print(f"发送麦克风录音失败: {e}")
                continue

            # 3.2 发送所有图片文件
            # 以下图片发送代码已被注释，暂时禁用。
            # for i, path in enumerate(image_paths):
            #     try:
            #         with open(path, "rb") as f:
            #             data = f.read()
            #         print(f"发送图片 {i+1}: {os.path.basename(path)} ({len(data)}字节)")
            #         await realtime_client.append_image(data)
            #         await asyncio.sleep(0.1)
            #     except Exception as e:
            #         print(f"发送图片 {os.path.basename(path)} 失败: {e}")

            # 3.3 提交并等待响应
            print("提交所有输入，请求服务器响应...")
            await realtime_client.commit_audio_buffer()
            await realtime_client.create_response()

            print("等待并播放服务器响应音频...")
            start_time = time.time()
            max_wait_time = 60
            while not audio_player.is_finished_playing():
                if time.time() - start_time > max_wait_time:
                    print(f"\n等待超时 ({max_wait_time}秒), 进入下一轮。")
                    break
                await asyncio.sleep(0.2)

            print("\n本轮音频播放完成！")
            turn_counter += 1

    except (asyncio.CancelledError, KeyboardInterrupt):
        print("\n程序被中断。")
    except Exception as e:
        print(f"发生未处理的错误: {e}")
    finally:
        # ------------------- 4. 清理资源 -------------------
        print("\n正在关闭连接并清理资源...")
        if message_handler_task and not message_handler_task.done():
            message_handler_task.cancel()

        if 'realtime_client' in locals() and realtime_client.ws and not realtime_client.ws.close:
            await realtime_client.close()
            print("连接已关闭。")

        audio_player.stop()
        print("程序退出。")

if __name__ == "__main__":
    try:
        asyncio.run(interactive_test())
    except KeyboardInterrupt:
        print("\n程序被用户强制退出。")
```

运行manual_mode.py，按 Enter 键开始说话，再按一次获取模型响应的音频。

import asyncio

from dotenv import load_dotenv

from dedalus_labs import AsyncDedalus, DedalusRunner
from dedalus_labs.utils.streaming import stream_async

load_dotenv()

async def main():
    client = AsyncDedalus()
    runner = DedalusRunner(client)
    response = await runner.run(
        input="How do I create the next big thing?",
        model="openai/gpt-4.1"
    )
    print(response.final_output)

if __name__ == "__main__":
    asyncio.run(main())
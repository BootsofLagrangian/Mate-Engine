"""Run the engine: python -m engine [--host 127.0.0.1] [--port 8876] (from companion/)."""
import argparse
import logging
import uvicorn


def main():
    parser = argparse.ArgumentParser(description='Mate companion engine (FastAPI + WebSocket)')
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8876)
    parser.add_argument('--log-level', default='info')
    args = parser.parse_args()
    logging.basicConfig(level=args.log_level.upper(), format='%(asctime)s %(name)s %(levelname)s %(message)s')
    uvicorn.run('engine.server:app', host=args.host, port=args.port, log_level=args.log_level, ws='websockets')


if __name__ == '__main__':
    main()

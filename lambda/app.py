import json
import os
from datetime import datetime
from typing import Dict, List

import boto3


S3_BUCKET_NAME = os.environ.get("S3_BUCKET_NAME", "")
CLOUDFRONT_DOMAIN = os.environ.get("CLOUDFRONT_DOMAIN", "")
DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE", "")
DEFAULT_INTERVAL_SECONDS = int(os.environ.get("DEFAULT_INTERVAL_SECONDS", "10"))


s3_client = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")


def _is_supported_media(key: str) -> bool:
    supported = (".jpg", ".jpeg", ".png", ".gif", ".mp4", ".mov", ".webm", ".avi")
    return key.lower().endswith(supported)


def _infer_media_type(key: str) -> str:
    if key.lower().endswith((".mp4", ".mov", ".webm", ".avi")):
        return "video"
    return "image"


def _get_academy_config(academy_id: str) -> Dict:
    if not DYNAMODB_TABLE:
        return {}
    table = dynamodb.Table(DYNAMODB_TABLE)
    res = table.get_item(Key={"academy_id": academy_id})
    return res.get("Item", {})


def _list_media_from_s3(academy_id: str) -> List[Dict]:
    prefix = f"academies/{academy_id}/"
    paginator = s3_client.get_paginator("list_objects_v2")
    media_items: List[Dict] = []

    for page in paginator.paginate(Bucket=S3_BUCKET_NAME, Prefix=prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if not _is_supported_media(key):
                continue
            media_items.append(
                {
                    "url": f"https://{CLOUDFRONT_DOMAIN}/{key}" if CLOUDFRONT_DOMAIN else f"https://{S3_BUCKET_NAME}.s3.amazonaws.com/{key}",
                    "type": _infer_media_type(key),
                    "filename": key.split("/")[-1],
                    "size": obj.get("Size"),
                    "last_modified": obj.get("LastModified").isoformat() if obj.get("LastModified") else None,
                }
            )

    media_items.sort(key=lambda m: m.get("last_modified") or "", reverse=True)
    return media_items


def lambda_handler(event, context):
    path = (event or {}).get("path", "")
    path_params = (event or {}).get("pathParameters", {}) or {}

    academy_id = path_params.get("academy_id")
    if not academy_id:
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
            "body": json.dumps({"error": "academy_id é obrigatório"}),
        }

    config = _get_academy_config(academy_id)
    media_list = _list_media_from_s3(academy_id)

    if "/playlist" in path:
        playlist_config = {
            "interval": int(config.get("interval", DEFAULT_INTERVAL_SECONDS)),
            "shuffle": bool(config.get("shuffle", True)),
            "loop": bool(config.get("loop", True)),
            "fade_transition": bool(config.get("fade_transition", True)),
            "academy_name": config.get("name", "Academia"),
            "timezone": config.get("timezone", "America/Sao_Paulo"),
        }
        resp = {
            "academy_id": academy_id,
            "playlist_config": playlist_config,
            "media_list": media_list,
            "total_items": len(media_list),
            "generated_at": datetime.utcnow().isoformat(),
        }
    else:
        resp = {"academy_id": academy_id, "media_list": media_list, "total_items": len(media_list)}

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Methods": "GET,OPTIONS",
        },
        "body": json.dumps(resp),
    }



#!/usr/bin/env python3
import json
import secrets
import sys
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")
BASE_URL = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8080").rstrip("/")
SMALLEST_VALID_JPEG = bytes.fromhex(
    "ffd8ffe000104a46494600010100000100010000ffdb004300080606070605080707070909080a0c140d0c0b0b0c1912130f141d1a1f1e1d1a1c1c20242e2720222c231c1c2837292c30313434341f27393d38323c2e333432ffc0000b080001000101011100ffc4001f0000010501010101010100000000000000000102030405060708090a0bffc400b5100002010303020403050504040000017d01020300041105122131410613516107227114328191a1082342b1c11552d1f02433627282090a161718191a25262728292a3435363738393a434445464748494a535455565758595a636465666768696a737475767778797a838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae1e2e3e4e5e6e7e8e9eaf1f2f3f4f5f6f7f8f9faffda0008010100003f00fbd3ffd9"
)

passed_checks = 0


def multipart_body(fields, boundary):
    parts = []
    for field_name, value in fields.items():
        if isinstance(value, bytes):
            parts.append(
                f'--{boundary}\r\nContent-Disposition: form-data; name="{field_name}"; filename="foto.jpg"\r\n'
                f"Content-Type: image/jpeg\r\n\r\n".encode() + value + b"\r\n"
            )
        else:
            parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{field_name}"\r\n\r\n{value}\r\n'.encode())
    return b"".join(parts) + f"--{boundary}--\r\n".encode()


def call_api(method, path, json_body=None, token=None, form=None, expected_status=200):
    headers = {}
    data = None
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if form is not None:
        boundary = secrets.token_hex(8)
        data = multipart_body(form, boundary)
        headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
    elif json_body is not None:
        data = json.dumps(json_body).encode()
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(BASE_URL + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request) as response:
            status, raw_body = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, raw_body = error.code, error.read()
    if status != expected_status:
        sys.exit(f"FALHOU {method} {path}: esperava {expected_status}, veio {status}: {raw_body[:300]!r}")
    looks_like_json = raw_body and raw_body[:1] in (b"{", b"[")
    return json.loads(raw_body) if looks_like_json else raw_body


def check(label, condition):
    global passed_checks
    if not condition:
        sys.exit(f"FALHOU: {label}")
    passed_checks += 1
    print(f"ok  {label}")


username = "teste_" + secrets.token_hex(3)
password = "senha-segura-123"

categories = call_api("GET", "/api/categories")
check("5 categorias embutidas", {category["slug"] for category in categories} >= {"filmes", "series", "albuns", "jogos", "livros"})

session = call_api("POST", "/api/auth/register", {"username": username, "password": password})
token = session["token"]
check("cadastro devolve token e usuário", session["user"]["username"] == username)
call_api("POST", "/api/auth/register", {"username": username, "password": password}, expected_status=409)
check("nome duplicado -> 409", True)
call_api("POST", "/api/auth/login", {"username": username.upper(), "password": password})
check("login ignora maiúsculas", True)
call_api("POST", "/api/auth/login", {"username": username, "password": "errada!!!"}, expected_status=401)
check("senha errada -> 401", True)
check("/api/me com token", call_api("GET", "/api/me", token=token)["username"] == username)

user = call_api("POST", "/api/me/avatar", token=token, form={"image": SMALLEST_VALID_JPEG})
check("upload de avatar", (user.get("avatarUrl") or "").startswith("/uploads/"))

category = call_api("POST", "/api/categories", {"name": "Vinhos Tintos " + username, "description": "teste"}, token=token)
check("categoria criada com slug", category["slug"].startswith("vinhos-tintos-"))
same_name_category = call_api("POST", "/api/categories", {"name": "Vinhos Tintos " + username, "description": None}, token=token)
check("slug repetido ganha sufixo", same_name_category["slug"] == category["slug"] + "-2")

manual_item = call_api(
    "POST",
    f"/api/categories/{category['slug']}/items",
    token=token,
    form={"title": "Malbec Reserva", "subtitle": "Mendoza", "year": "2019", "description": "tinto", "image": SMALLEST_VALID_JPEG},
)
check("item manual com foto", manual_item["year"] == 2019 and manual_item["imageUrl"].startswith("/uploads/"))
search_hits = call_api("GET", f"/api/categories/{category['slug']}/search?q=MALBEC")
check("busca local ignora maiúsculas (ILIKE)", any(hit["itemId"] == manual_item["id"] for hit in search_hits))
search_hits = call_api("GET", f"/api/categories/{category['slug']}/search?q=100%25")
check("busca com % não casa tudo", search_hits == [])
category_items = call_api("GET", f"/api/categories/{category['slug']}/items")
check("lista de itens da categoria", [item["id"] for item in category_items] == [manual_item["id"]])

external_book = {
    "source": "openlibrary",
    "externalId": "teste-" + username,
    "title": "Dom Casmurro",
    "subtitle": "Machado de Assis",
    "year": 1899,
    "imageUrl": None,
    "description": None,
}
first_import = call_api("POST", "/api/categories/livros/import", external_book, token=token)
second_import = call_api("POST", "/api/categories/livros/import", {**external_book, "title": "Dom Casmurro (ed. revista)"}, token=token)
check("importação idempotente (ON CONFLICT)", first_import["id"] == second_import["id"] and second_import["title"].endswith("revista)"))
call_api("POST", "/api/categories/filmes/import", external_book, token=token, expected_status=400)
check("importar na categoria errada -> 400", True)

book_reviews_path = f"/api/items/{first_import['id']}/reviews"
loved_review = call_api("POST", book_reviews_path, {"rating": 9, "body": "Capitu!", "liked": True, "consumedOn": "2024-03-10"}, token=token)
call_api("POST", book_reviews_path, {"rating": 6, "body": None, "liked": False, "consumedOn": None}, token=token)
check("review com data e ♥", loved_review["liked"] is True and loved_review["consumedOn"] == "2024-03-10")
call_api("POST", book_reviews_path, {"rating": 11, "body": None, "liked": False, "consumedOn": None}, token=token, expected_status=400)
check("nota fora de 1–10 -> 400", True)

book_detail = call_api("GET", f"/api/items/{first_import['id']}")
check("média e contagem", book_detail["ratingCount"] == 2 and abs(book_detail["averageRating"] - 7.5) < 1e-9)
check("detalhe traz categoria e reviews", book_detail["category"]["slug"] == "livros" and len(book_detail["reviews"]) == 2)

diary = call_api("GET", f"/api/users/{username.upper()}/diary")
check("diário (2 entradas, data mais recente primeiro)", len(diary) == 2 and diary[0]["review"]["consumedOn"] is None)

call_api("DELETE", f"/api/reviews/{loved_review['id']}", token=token, expected_status=204)
check("excluir review", call_api("GET", f"/api/items/{first_import['id']}")["ratingCount"] == 1)
call_api("DELETE", f"/api/reviews/{loved_review['id']}", token=token, expected_status=404)
check("excluir de novo -> 404", True)

call_api("POST", "/api/auth/logout", token=token, expected_status=204)
call_api("GET", "/api/me", token=token, expected_status=401)
check("logout invalida o token", True)

print(f"\n{passed_checks} verificações passaram contra {BASE_URL}")

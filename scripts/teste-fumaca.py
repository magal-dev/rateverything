#!/usr/bin/env python3
"""Teste de fumaça da API contra um servidor rodando (e seu banco).

    python3 scripts/teste-fumaca.py http://localhost:8080

Exercita todas as rotas que tocam o banco: cadastro/login (inclusive nome
duplicado com outra caixa), sessão, categorias, itens manuais com foto,
importação idempotente, busca sem diferenciar maiúsculas, reviews, média,
diário e exclusão. Só usa a biblioteca padrão. Cria dados com nome aleatório.
"""
import json
import secrets
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8080").rstrip("/")
# Menor JPEG válido (1x1), para o upload passar pela validação de magic bytes.
JPEG = bytes.fromhex(
    "ffd8ffe000104a46494600010100000100010000ffdb004300080606070605080707070909080a0c140d0c0b0b0c1912130f141d1a1f1e1d1a1c1c20242e2720222c231c1c2837292c30313434341f27393d38323c2e333432ffc0000b080001000101011100ffc4001f0000010501010101010100000000000000000102030405060708090a0bffc400b5100002010303020403050504040000017d01020300041105122131410613516107227114328191a1082342b1c11552d1f02433627282090a161718191a25262728292a3435363738393a434445464748494a535455565758595a636465666768696a737475767778797a838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae1e2e3e4e5e6e7e8e9eaf1f2f3f4f5f6f7f8f9faffda0008010100003f00fbd3ffd9"
)

passed = 0


def call(method, path, body=None, token=None, form=None, expect=200):
    headers = {}
    data = None
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if form is not None:
        boundary = secrets.token_hex(8)
        parts = []
        for name, value in form.items():
            if isinstance(value, bytes):
                parts.append(
                    f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"; filename="foto.jpg"\r\n'
                    f"Content-Type: image/jpeg\r\n\r\n".encode() + value + b"\r\n"
                )
            else:
                parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
        data = b"".join(parts) + f"--{boundary}--\r\n".encode()
        headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
    elif body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            status, raw = resp.status, resp.read()
    except urllib.error.HTTPError as e:
        status, raw = e.code, e.read()
    if status != expect:
        sys.exit(f"FALHOU {method} {path}: esperava {expect}, veio {status}: {raw[:300]!r}")
    return json.loads(raw) if raw and raw[:1] in (b"{", b"[") else raw


def check(label, cond):
    global passed
    if not cond:
        sys.exit(f"FALHOU: {label}")
    passed += 1
    print(f"ok  {label}")


name = "teste_" + secrets.token_hex(3)
password = "senha-segura-123"

cats = call("GET", "/api/categories")
check("5 categorias embutidas", {c["slug"] for c in cats} >= {"filmes", "series", "albuns", "jogos", "livros"})

session = call("POST", "/api/auth/register", {"username": name, "password": password})
token = session["token"]
check("cadastro devolve token e usuário", session["user"]["username"] == name)
call("POST", "/api/auth/register", {"username": name, "password": password}, expect=409)
check("nome duplicado -> 409", True)
call("POST", "/api/auth/login", {"username": name.upper(), "password": password})
check("login ignora maiúsculas", True)
call("POST", "/api/auth/login", {"username": name, "password": "errada!!!"}, expect=401)
check("senha errada -> 401", True)
check("/api/me com token", call("GET", "/api/me", token=token)["username"] == name)

user = call("POST", "/api/me/avatar", token=token, form={"image": JPEG})
check("upload de avatar", (user.get("avatarUrl") or "").startswith("/uploads/"))

cat = call("POST", "/api/categories", {"name": "Vinhos Tintos " + name, "description": "teste"}, token=token)
check("categoria criada com slug", cat["slug"].startswith("vinhos-tintos-"))
cat2 = call("POST", "/api/categories", {"name": "Vinhos Tintos " + name, "description": None}, token=token)
check("slug repetido ganha sufixo", cat2["slug"] == cat["slug"] + "-2")

item = call(
    "POST",
    f"/api/categories/{cat['slug']}/items",
    token=token,
    form={"title": "Malbec Reserva", "subtitle": "Mendoza", "year": "2019", "description": "tinto", "image": JPEG},
)
check("item manual com foto", item["year"] == 2019 and item["imageUrl"].startswith("/uploads/"))
hits = call("GET", f"/api/categories/{cat['slug']}/search?q=MALBEC")
check("busca local ignora maiúsculas (ILIKE)", any(h["itemId"] == item["id"] for h in hits))
hits = call("GET", f"/api/categories/{cat['slug']}/search?q=100%25")
check("busca com % não casa tudo", hits == [])
check("lista de itens da categoria", [i["id"] for i in call("GET", f"/api/categories/{cat['slug']}/items")] == [item["id"]])

ext = {
    "source": "openlibrary",
    "externalId": "teste-" + name,
    "title": "Dom Casmurro",
    "subtitle": "Machado de Assis",
    "year": 1899,
    "imageUrl": None,
    "description": None,
}
imp1 = call("POST", "/api/categories/livros/import", ext, token=token)
imp2 = call("POST", "/api/categories/livros/import", {**ext, "title": "Dom Casmurro (ed. revista)"}, token=token)
check("importação idempotente (ON CONFLICT)", imp1["id"] == imp2["id"] and imp2["title"].endswith("revista)"))
call("POST", "/api/categories/filmes/import", ext, token=token, expect=400)
check("importar na categoria errada -> 400", True)

r1 = call("POST", f"/api/items/{imp1['id']}/reviews", {"rating": 9, "body": "Capitu!", "liked": True, "consumedOn": "2024-03-10"}, token=token)
call("POST", f"/api/items/{imp1['id']}/reviews", {"rating": 6, "body": None, "liked": False, "consumedOn": None}, token=token)
check("review com data e ♥", r1["liked"] is True and r1["consumedOn"] == "2024-03-10")
call("POST", f"/api/items/{imp1['id']}/reviews", {"rating": 11, "body": None, "liked": False, "consumedOn": None}, token=token, expect=400)
check("nota fora de 1–10 -> 400", True)

detail = call("GET", f"/api/items/{imp1['id']}")
check("média e contagem", detail["ratingCount"] == 2 and abs(detail["averageRating"] - 7.5) < 1e-9)
check("detalhe traz categoria e reviews", detail["category"]["slug"] == "livros" and len(detail["reviews"]) == 2)

diary = call("GET", f"/api/users/{name.upper()}/diary")
check("diário (2 entradas, data mais recente primeiro)", len(diary) == 2 and diary[0]["review"]["consumedOn"] is None)

call("DELETE", f"/api/reviews/{r1['id']}", token=token, expect=204)
check("excluir review", call("GET", f"/api/items/{imp1['id']}")["ratingCount"] == 1)
call("DELETE", f"/api/reviews/{r1['id']}", token=token, expect=404)
check("excluir de novo -> 404", True)

call("POST", "/api/auth/logout", token=token, expect=204)
call("GET", "/api/me", token=token, expect=401)
check("logout invalida o token", True)

print(f"\n{passed} verificações passaram contra {BASE}")

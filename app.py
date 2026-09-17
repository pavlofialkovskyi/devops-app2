import os                                       # import statement — brings in code from elsewhere
import psycopg2                                 # import statement
from psycopg2.extras import RealDictCursor      # import statement
from flask import Flask, jsonify, request

app = Flask(__name__)    # OBJECT — one instance of the Flask class, named "app". No new class created here.

def get_db_connection():                   # FUNCTION — plain, standalone, not inside any class             
    return psycopg2.connect(
        host=os.environ.get("DB_HOST"),
        port=os.environ.get("DB_PORT"),
        dbname=os.environ.get("DB_NAME"),
        user=os.environ.get("DB_USER"),
        password=os.environ.get("DB_PASSWORD"),
    )

@app.route("/messages", methods=["GET"])   # DECORATOR — registers the function below with Flask
def get_messages():                        # FUNCTION — again, plain, standalone
    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("SELECT id, image_url, content, created_at FROM messages ORDER BY id;")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return jsonify(rows)

@app.route("/messages", methods=["POST"])
def create_message():
    data = request.get_json()
    content = data.get("content")
    image_url = data.get("image_url")
    if not content:
        return jsonify({"error": "content is required"}), 400

    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute(
        "INSERT INTO messages (content, image_url) VALUES (%s, %s) RETURNING id, content, image_url, created_at;",
        (content, image_url),
    )
    new_row = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()
    return jsonify(new_row), 201

@app.route("/messages/<int:message_id>", methods=["PUT"])
def update_message(message_id):
    data = request.get_json()
    content = data.get("content")
    image_url = data.get("image_url")
    if not content:
        return jsonify({"error": "content is required"}), 400

    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute(
        "UPDATE messages SET content = %s, image_url = %s WHERE id = %s RETURNING id, content, image_url, created_at;",
        (content, image_url, message_id),
    )
    updated_row = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()

    if updated_row is None:
        return jsonify({"error": "message not found"}), 404
    return jsonify(updated_row)

@app.route("/messages/<int:message_id>", methods=["DELETE"])
def delete_message(message_id):
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("DELETE FROM messages WHERE id = %s;", (message_id,))
    deleted_count = cur.rowcount
    conn.commit()
    cur.close()
    conn.close()

    if deleted_count == 0:
        return jsonify({"error": "message not found"}), 404
    return "", 204

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
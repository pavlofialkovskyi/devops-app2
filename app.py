import os
import uuid                                     
#----- used to generate random, collision-proof file names
import psycopg2
import boto3                                   
#----- AWS SDK for Python — lets us talk to S3
from botocore.config import Config
#27----- dependensy for a s3 local emulator called minIO


from psycopg2.extras import RealDictCursor
from flask import Flask, jsonify, request

##----- OBJECT — one instance of the Flask class, named "app".
app = Flask(__name__)    


#24 read the bucket's name from the environment and stores it in the Python variable S3_Bucket
S3_BUCKET = os.environ.get("S3_UPLOADS_BUCKET")
#24 boto3.client("s3") sets up a connection to S3, the same idea as get_db_connection() below 
# sets up a connection to Postgres — just a different service, different library.
#27 setting the S3_ENDPOINT_URL locally in docker-compose, the http://minio:9000 for the web service
# so boto3 connects to our env cointainer minIO instead of real AWS
# in production the env.var is never set, so endpoint_url is None, and boto3 talks to aws by default 
S3_ENDPOINT_URL = os.environ.get("S3_ENDPOINT_URL")

#31 redirecting the minIO:9000 to localhost:9000 access
S3_PUBLIC_ENDPOINT_URL = os.environ.get("S3_PUBLIC_ENDPOINT_URL", S3_ENDPOINT_URL)

s3 = boto3.client(
    "s3",
    endpoint_url=S3_ENDPOINT_URL,
    config=Config(s3={"addressing_style": "path"}),
)

#31 Public url for s3 minIO redirected to localhost

s3_public = boto3.client(
    "s3",
    endpoint_url=S3_PUBLIC_ENDPOINT_URL,
    config=Config(s3={"addressing_style": "path"}),
)

# "addressing_style": "path" - s required for MinIO to work correctly, 
#  and it's harmless to leave on even against real AWS, withtout need of if/else condition



def get_db_connection():                   
    return psycopg2.connect(
        host=os.environ.get("DB_HOST"),
        port=os.environ.get("DB_PORT"),
        dbname=os.environ.get("DB_NAME"),
        user=os.environ.get("DB_USER"),
        password=os.environ.get("DB_PASSWORD"),
    )

#------- Method to create a temporal url on any fetch action in chat---------

def with_download_url(row):
##----- The file itself is private in S3, named with a random UUID (media_key), not its real filename. 
# This function asks S3 for a temporary [[every time THIS chat sessions asks to fetch the file]], 
# secure link (valid for 5 minutes) that lets someone actually download the file — and tells S3 
# to present it under its real name (original_filename) instead of the UUID. Nothing about the file's 
# actual storage changes; this link is generated fresh every time a row is read, it's never itself 
# stored anywhere.
    if row.get("media_key"):
        row["media_url"] = s3_public.generate_presigned_url(
            "get_object",
            Params={
                "Bucket": S3_BUCKET,
                "Key": row["media_key"],
                "ResponseContentDisposition": f'attachment; filename="{row["original_filename"]}"',
            },
            ExpiresIn=300,  # the LINK expires in 5 minutes — the file in S3 does not
        )
    return row



#---------- Method to POST the media file, or CV, in the S3 Bucket -------------

#------ Frontend sends the file to S3, and Flask generates a new UUID name for this file,
# than Flask sends this to Frontend and tells the new UUID name, so Frontend keeps in JAVASCRIPT the 
# new name and the original name temporary"

@app.route("/uploads/presign", methods=["POST"])   
def presign_upload():
#----- Step 1 of sending a file (separate from sending a text message, per the frontend's design: 
# the file picker fires this immediately, on its own, never combined with the text-message Send button 
# in one action). This endpoint does NOT touch Postgres — get_db_connection() is not called here because 
# nothing is being saved yet. All it does is ask S3 for a temporary "permission slip" (a presigned URL) 
# that lets the frontend upload the raw file directly to S3 a moment later. 
    data = request.get_json()
    original_filename = data.get("filename")
#----- Defensive check on the REQUEST itself, not on "a file with no name" — guards against 
# a malformed/empty request body (e.g. a frontend bug, or someone calling this API directly during testing) 
# so it fails cleanly with a 400 instead of crashing further down.
    if not original_filename:
        return jsonify({"error": "filename is required"}), 400
#----- Random UUID instead of hashing the file's content — hashing content would cause 
# two different people uploading the identical file to collide on the same S3 key. 
# A UUID is random and independent of the file itself, so collisions are effectively impossible 
# regardless of content.
    ext = os.path.splitext(original_filename)[1]
    media_key = f"{uuid.uuid4()}{ext}"
#----- this is what Flask sends as a new name to Frontend, to store in JS

#31 changed the presigned upload link to publc presigned url
    upload_url = s3_public.generate_presigned_url(
        "put_object",
        Params={"Bucket": S3_BUCKET, "Key": media_key},
        ExpiresIn=300,  
##----- 5 minutes to actually complete the upload before this link dies
    )
    return jsonify({
        "upload_url": upload_url,
        "media_key": media_key,
        "original_filename": original_filename,
    })


#--------- Method to download file from chat, with_download_url generates a temporal 5 min link -------

@app.route("/messages", methods=["GET"])   
def get_messages():                        
    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)

    limit = request.args.get("limit", default=50, type=int)
    offset = request.args.get("offset", default=0, type=int)
# pagination is set to 50 

    cur.execute(
    "SELECT id, content, media_key, original_filename, created_at FROM messages "
    "ORDER BY id LIMIT %s OFFSET %s;",
    (limit, offset),
    )

    rows = cur.fetchall()
    cur.close()
    conn.close()
##----- Every row that has a file attached gets a fresh (chat refresh), temporary download link 
# generated right now — links are never stored, only generated on read.
    rows = [with_download_url(row) for row in rows]
    return jsonify(rows)



#-------------File is on S3 -> Flaks pushes the UUID and Original name to Flask -> than to Postgres 
# -> Postgres has the utility to send back a RETURNING JSON with all the data in this ID, it works 
# both for confirming that the POSTing was successful and also gives an order for flask to tell 
# about it to Frontend -> Before the POST was done, Frontend had this file in a OPTIMISTIC State 
# "pending" -> if POST to Postgres failed Flask tells about it and the status is "failed" 
# displayed in chat -> if POSTed well, then in chat you will see a message "file sent"
#-------------"state" in the technical sense: a piece of data the frontend keeps track of 
# describing what's currently true on screen, separate from what's actually confirmed in the database. 
# Concretely, each message in that chat would have a status field the frontend manages itself, 
# something like "pending" (just clicked send, waiting on Flask), "sent" (Flask's RETURNING response 
# came back with the real id, everything confirmed), or "failed" (the request errored or timed out)


@app.route("/messages", methods=["POST"])
def create_message():
#----- Step 2 of sending a file (or the only step, for a plain text message): the frontend 
# calls this AFTER a file has already been uploaded straight to S3 using the presigned URL 
# from /uploads/presign — this is where the media_key and original_filename actually get 
# saved into Postgres.     
#----- Per how the frontend works, content and media_key are never both sent together in the same 
# request (typing+Send and picking a file are two separate, independent actions) — so this only needs 
# to check that ATLEast one of them is present, not guard against both arriving at once.
    data = request.get_json()
    content = data.get("content")
    media_key = data.get("media_key")
    original_filename = data.get("original_filename")

    if not content and not media_key:
        return jsonify({"error": "content or a file is required"}), 400

    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute(
        "INSERT INTO messages (content, media_key, original_filename) VALUES (%s, %s, %s) "
#----- RETURNING is Postgres SQL syntax, not a new column: it means "insert this row, 
# then immediately hand back these column values from the row you just created" — in ONE trip 
# to the database, instead of a separate SELECT query afterward to go look the new row back up.
#----- The frontend needs this: it doesn't know the new row's real "id" or "created_at" until Postgres 
# assigns them at insert time.
        "RETURNING id, content, media_key, original_filename, created_at;",
        (content, media_key, original_filename),
    )
    new_row = cur.fetchone()   
# fetches the row RETURNING just handed back
    conn.commit()
    cur.close()
    conn.close()
    return jsonify(with_download_url(new_row)), 201


#------------ PUT method, in case you want to edit the chat message------------

#------ If we want to have EDITED badge next to the updated message, we can 
# add 1 more column in the Postgres, called "edited_at" and keep it NULL for original value, 
# or "present" if it was edited. The backend just needs to include edited_at in the same JSON 
# it already sends back from get_messages/update_message — nothing extra to "ask for," it rides 
# along automatically with the rest of that row's data on every normal fetch. The frontend then 
# simply checks, for each message it renders, whether edited_at is present or null, and shows 
# the "edited" badge next to it if it isn't null — a plain conditional in the display code, 
# not a separate request.


@app.route("/messages/<int:message_id>", methods=["PUT"])
def update_message(message_id):
    data = request.get_json()
    content = data.get("content")
    media_key = data.get("media_key")
    original_filename = data.get("original_filename")

    if not content and not media_key:
        return jsonify({"error": "content or a file is required"}), 400

    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute(
        "UPDATE messages SET content = %s, media_key = %s, original_filename = %s WHERE id = %s "
        "RETURNING id, content, media_key, original_filename, created_at;",
        (content, media_key, original_filename, message_id),
    )
    updated_row = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()

    if updated_row is None:
        return jsonify({"error": "message not found"}), 404
    return jsonify(with_download_url(updated_row))


@app.route("/messages/<int:message_id>", methods=["DELETE"])
def delete_message(message_id):
#----- Deletes the whole message. If it had a file attached, that file is also deleted from S3 here, 
# so nothing gets left behind (orphaned) in the bucket once its owning message no longer exists.
    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("SELECT media_key FROM messages WHERE id = %s;", (message_id,))
    row = cur.fetchone()

    if row is None:
        cur.close()
        conn.close()
        return jsonify({"error": "message not found"}), 404

    cur.execute("DELETE FROM messages WHERE id = %s;", (message_id,))
    conn.commit()
    cur.close()
    conn.close()

    if row["media_key"]:
        try: 
            s3.delete_object(Bucket=S3_BUCKET, Key=row["media_key"])
        except Exception as e:
            app.logger.error(f"Failed to delete s3 Media File {row[ 'media_key']}: {e}")

      

# just for fun I left this method under if condition, though no file uploaded to S3 
# when the message is sent, but we had actually 2 DELETE methods and 2nd one was to delete 
# a Media File or CV file without touching the content. But because we are sending file and 
# text message separately, we can delete any message_id content with this Delete method and 
# if CONDITION returns that there was actually a Media Key UUID file stored  in s3 -> we delete 
# the file in s3 and the row in Postgres. This is great because no Storage Leak in s3 is happening.

    return "", 204




@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
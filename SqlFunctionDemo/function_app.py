import azure.functions as func
import pyodbc
import os
import datetime
import logging

app = func.FunctionApp()

@app.function_name(name="ProcessFile")
@app.route(route="processfile", methods=["post"])
def ProcessFile(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Processing file request...")

    try:
        sql_conn_str = os.environ["SQL_CONNECTION_STRING"]

        conn = pyodbc.connect(sql_conn_str)
        cursor = conn.cursor()

        data = req.get_json()

        file_name = data.get("fileName")
        content = data.get("content")

        cursor.execute("""
            INSERT INTO ProcessedFiles (FileName, ProcessedTime, Status, Content)
            VALUES (?, ?, ?, ?)
        """, file_name, datetime.datetime.utcnow(), "Processed", content)

        conn.commit()
        cursor.close()

        return func.HttpResponse("Inserted Successfully", status_code=200)

    except Exception as e:
        logging.error(str(e))
        return func.HttpResponse(f"Error: {str(e)}", status_code=500)

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import os
import uvicorn

app = FastAPI(title="WizKnowledge - AI Q&A System")

class Question(BaseModel):
    question: str
    context: str = ""

@app.get("/")
def root():
    return {
        "message": "WizKnowledge AI Q&A System",
        "status": "operational",
        "environment": os.getenv("ENVIRONMENT", "unknown")
    }

@app.post("/ask")
async def ask_question(question: Question):
    # Simplified for initial setup
    return {
        "answer": f"This is a demo answer for: {question.question}",
        "stored": True
    }

@app.get("/health")
def health_check():
    return {"status": "healthy"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)

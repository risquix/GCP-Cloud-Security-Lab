#!/usr/bin/env python3
"""
WizKnowledge AI Q&A System with User Authentication
A security lab application demonstrating various vulnerabilities and secure coding practices
"""

import os
import logging
from datetime import datetime, timedelta
from typing import Optional, List
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Depends, Request, Form, Cookie
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel, EmailStr, field_validator
from pymongo import MongoClient
from passlib.context import CryptContext
from jose import JWTError, jwt
import uvicorn


# Configuration
SECRET_KEY = os.getenv("SECRET_KEY", "vulnerable-secret-key-123")  # VULNERABILITY: Weak default secret
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30
MONGODB_URI = os.getenv("MONGODB_URI", "mongodb://localhost:27017/wizknowledge")

# Security setup
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
security = HTTPBearer(auto_error=False)

# Database connection
mongodb_client = None
db = None

# Templates setup
templates = Jinja2Templates(directory="templates")

# Logging setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Pydantic models
class UserRegistration(BaseModel):
    username: str
    email: EmailStr
    password: str
    confirm_password: str
    
    @field_validator('username')
    def username_alphanumeric(cls, v):
        if len(v) < 3:
            raise ValueError('Username must be at least 3 characters long')
        return v
    
    @field_validator('confirm_password')
    def passwords_match(cls, v, values, **kwargs):
        if hasattr(values, 'data') and 'password' in values.data and v != values.data['password']:
            raise ValueError('Passwords do not match')
        return v


class UserLogin(BaseModel):
    username: str
    password: str


class ChatMessage(BaseModel):
    message: str


class User(BaseModel):
    id: Optional[str] = None
    username: str
    email: str
    created_at: Optional[datetime] = None
    is_active: bool = True


class Chat(BaseModel):
    id: Optional[str] = None
    user_id: str
    message: str
    response: str
    timestamp: Optional[datetime] = None


# Database functions
async def get_database():
    """Get database connection"""
    global mongodb_client, db
    if mongodb_client is None:
        try:
            mongodb_client = MongoClient(MONGODB_URI)
            db = mongodb_client.get_default_database()
            logger.info("Connected to MongoDB")
            
            # Create indexes for performance
            db.users.create_index("username", unique=True)
            db.users.create_index("email", unique=True)
            db.chats.create_index([("user_id", 1), ("timestamp", -1)])
        except Exception as e:
            logger.error(f"MongoDB connection failed: {e}")
            db = None
    return db


# Authentication functions
def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password):
    return pwd_context.hash(password)


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=15)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt


async def get_current_user(request: Request, credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Get current user from JWT token"""
    token = None
    
    # Try to get token from Authorization header
    if credentials:
        token = credentials.credentials
    
    # Try to get token from cookie
    if not token:
        token = request.cookies.get("access_token")
    
    if not token:
        return None
    
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            return None
    except JWTError:
        return None
    
    db = await get_database()
    if db is None:
        return None
        
    user = db.users.find_one({"username": username})
    if user is None:
        return None
    
    return User(
        id=str(user["_id"]),
        username=user["username"],
        email=user["email"],
        created_at=user.get("created_at"),
        is_active=user.get("is_active", True)
    )


async def get_current_active_user(current_user: User = Depends(get_current_user)):
    if current_user is None:
        raise HTTPException(status_code=401, detail="Not authenticated")
    if not current_user.is_active:
        raise HTTPException(status_code=400, detail="Inactive user")
    return current_user


# App lifespan
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    await get_database()
    yield
    # Shutdown
    if mongodb_client:
        mongodb_client.close()


# FastAPI app
app = FastAPI(
    title="WizKnowledge AI Q&A System",
    description="A security lab application with user authentication and chat features",
    version="2.0.0",
    lifespan=lifespan
)

# Static files and templates
try:
    app.mount("/static", StaticFiles(directory="static"), name="static")
except RuntimeError:
    # Directory doesn't exist, create it
    os.makedirs("static", exist_ok=True)
    app.mount("/static", StaticFiles(directory="static"), name="static")


# Routes
@app.get("/", response_class=HTMLResponse)
async def home(request: Request, current_user: Optional[User] = Depends(get_current_user)):
    """Home page"""
    return templates.TemplateResponse("index.html", {
        "request": request,
        "user": current_user,
        "title": "WizKnowledge AI Q&A System"
    })


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.utcnow()}


@app.get("/register", response_class=HTMLResponse)
async def register_form(request: Request):
    """Registration form"""
    return templates.TemplateResponse("register.html", {
        "request": request,
        "title": "Register - WizKnowledge"
    })


@app.post("/register")
async def register_user(
    username: str = Form(...),
    email: str = Form(...),
    password: str = Form(...),
    confirm_password: str = Form(...)
):
    """Register a new user"""
    db = await get_database()
    if db is None:
        raise HTTPException(status_code=500, detail="Database connection failed")
    
    # Validate passwords match
    if password != confirm_password:
        raise HTTPException(status_code=400, detail="Passwords do not match")
    
    # VULNERABILITY: Weak password validation
    if len(password) < 3:  # Should be much stronger
        raise HTTPException(status_code=400, detail="Password too short")
    
    # Check if user already exists
    if db.users.find_one({"username": username}):
        raise HTTPException(status_code=400, detail="Username already registered")
    
    if db.users.find_one({"email": email}):
        raise HTTPException(status_code=400, detail="Email already registered")
    
    # Create new user
    hashed_password = get_password_hash(password)
    user_doc = {
        "username": username,
        "email": email,
        "password_hash": hashed_password,
        "created_at": datetime.utcnow(),
        "is_active": True
    }
    
    result = db.users.insert_one(user_doc)
    
    # Create access token
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": username}, expires_delta=access_token_expires
    )
    
    # Set cookie and redirect
    response = RedirectResponse(url="/dashboard", status_code=302)
    response.set_cookie(
        key="access_token",
        value=access_token,
        max_age=ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        httponly=True,  # SECURITY: Prevent XSS access to token
        secure=False,  # VULNERABILITY: Should be True in production
        samesite="lax"
    )
    
    return response


@app.get("/login", response_class=HTMLResponse)
async def login_form(request: Request):
    """Login form"""
    return templates.TemplateResponse("login.html", {
        "request": request,
        "title": "Login - WizKnowledge"
    })


@app.post("/login")
async def login_user(username: str = Form(...), password: str = Form(...)):
    """Login user"""
    db = await get_database()
    if db is None:
        raise HTTPException(status_code=500, detail="Database connection failed")
    
    # Find user
    user = db.users.find_one({"username": username})
    if not user or not verify_password(password, user["password_hash"]):
        # VULNERABILITY: Detailed error message reveals if username exists
        raise HTTPException(status_code=400, detail="Incorrect username or password")
    
    # Create access token
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user["username"]}, expires_delta=access_token_expires
    )
    
    # Set cookie and redirect
    response = RedirectResponse(url="/dashboard", status_code=302)
    response.set_cookie(
        key="access_token",
        value=access_token,
        max_age=ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        httponly=True,
        secure=False,  # VULNERABILITY: Should be True in production
        samesite="lax"
    )
    
    return response


@app.get("/logout")
async def logout():
    """Logout user"""
    response = RedirectResponse(url="/", status_code=302)
    response.delete_cookie(key="access_token")
    return response


@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard(request: Request, current_user: User = Depends(get_current_active_user)):
    """User dashboard with chat interface"""
    db = await get_database()
    
    # Get user's recent chats
    chats = []
    if db is not None:
        chat_docs = db.chats.find(
            {"user_id": current_user.id}
        ).sort("timestamp", -1).limit(20)
        
        for chat in chat_docs:
            chats.append({
                "id": str(chat["_id"]),
                "message": chat["message"],
                "response": chat["response"],
                "timestamp": chat["timestamp"]
            })
    
    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "user": current_user,
        "chats": chats,
        "title": f"Dashboard - {current_user.username}"
    })


@app.post("/api/chat")
async def chat_endpoint(
    message: str = Form(...),
    current_user: User = Depends(get_current_active_user)
):
    """Process chat message and return response"""
    db = await get_database()
    
    if not message.strip():
        raise HTTPException(status_code=400, detail="Message cannot be empty")
    
    # VULNERABILITY: No input sanitization
    # Generate AI response (mock implementation)
    ai_response = await generate_ai_response(message)
    
    # Save chat to database
    if db is not None:
        chat_doc = {
            "user_id": current_user.id,
            "message": message,
            "response": ai_response,
            "timestamp": datetime.utcnow()
        }
        db.chats.insert_one(chat_doc)
    
    return {
        "message": message,
        "response": ai_response,
        "timestamp": datetime.utcnow().isoformat()
    }


@app.get("/api/chats")
async def get_user_chats(current_user: User = Depends(get_current_active_user)):
    """Get user's chat history"""
    db = await get_database()
    if db is None:
        return {"chats": []}
    
    chat_docs = db.chats.find(
        {"user_id": current_user.id}
    ).sort("timestamp", -1).limit(50)
    
    chats = []
    for chat in chat_docs:
        chats.append({
            "id": str(chat["_id"]),
            "message": chat["message"],
            "response": chat["response"],
            "timestamp": chat["timestamp"].isoformat()
        })
    
    return {"chats": chats}


@app.get("/api/users/me")
async def get_current_user_info(current_user: User = Depends(get_current_active_user)):
    """Get current user information"""
    return current_user


async def generate_ai_response(message: str) -> str:
    """Generate AI response (mock implementation)"""
    # VULNERABILITY: No rate limiting
    # VULNERABILITY: Potential for injection attacks if integrated with real AI
    
    # Mock responses based on keywords
    message_lower = message.lower()
    
    if "security" in message_lower or "vulnerability" in message_lower:
        return "Security is crucial in application development. Always validate input, use HTTPS, implement proper authentication, and keep dependencies updated. What specific security topic would you like to know more about?"
    
    elif "password" in message_lower:
        return "Password security best practices include: using strong, unique passwords; enabling multi-factor authentication; storing passwords using secure hashing algorithms like bcrypt; and never storing passwords in plain text."
    
    elif "sql injection" in message_lower or "sqli" in message_lower:
        return "SQL injection occurs when user input is directly included in SQL queries. Prevent it by using parameterized queries, stored procedures, or ORM frameworks that handle input sanitization automatically."
    
    elif "xss" in message_lower or "cross-site scripting" in message_lower:
        return "Cross-Site Scripting (XSS) attacks inject malicious scripts into web pages. Prevent XSS by sanitizing user input, using Content Security Policy headers, and encoding output properly."
    
    elif "hello" in message_lower or "hi" in message_lower:
        return f"Hello! I'm WizKnowledge AI, your security-focused assistant. I can help you with cybersecurity questions, secure coding practices, and general IT security topics. What would you like to know?"
    
    else:
        return f"Thank you for your question: '{message}'. While I'm a mock AI assistant in this security lab environment, I can help with security-related topics like secure coding, vulnerability assessment, and cybersecurity best practices. Could you ask something more specific about security?"


if __name__ == "__main__":
    # VULNERABILITY: Debug mode enabled in production-like code
    uvicorn.run(
        "app:app",
        host="0.0.0.0",
        port=int(os.getenv("PORT", 8080)),
        reload=True,  # VULNERABILITY: Should be False in production
        log_level="info"
    )
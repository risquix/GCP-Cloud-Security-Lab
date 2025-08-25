import os
import logging
from typing import Tuple
import vertexai
from vertexai.language_models import TextGenerationModel
from google.cloud import aiplatform

logger = logging.getLogger(__name__)

class RAGEngine:
    def __init__(self):
        """Initialize the RAG engine with Vertex AI"""
        try:
            project_id = os.getenv("GCP_PROJECT_ID", "clgcporg10-173")
            location = os.getenv("GCP_LOCATION", "us-central1")
            
            # Initialize Vertex AI
            vertexai.init(project=project_id, location=location)
            
            # Use text-bison model
            self.model = TextGenerationModel.from_pretrained("text-bison")
            
            logger.info(f"RAG Engine initialized for project {project_id}")
        except Exception as e:
            logger.error(f"Failed to initialize RAG engine: {str(e)}")
            raise
    
    async def get_answer(self, question: str, context: str = "") -> Tuple[str, float]:
        """
        Generate an answer using RAG approach
        Returns: (answer, confidence_score)
        """
        try:
            # Build prompt with context
            prompt = self._build_prompt(question, context)
            
            # Generate response
            response = self.model.predict(
                prompt,
                temperature=0.7,
                max_output_tokens=512,
                top_k=40,
                top_p=0.8,
            )
            
            # Calculate confidence (simplified)
            confidence = self._calculate_confidence(response.text, question)
            
            logger.info(f"Generated answer with confidence: {confidence}")
            
            return response.text, confidence
        except Exception as e:
            logger.error(f"Error generating answer: {str(e)}")
            # Fallback response
            return f"I apologize, but I'm unable to generate an answer at this time. Error: {str(e)}", 0.0
    
    def _build_prompt(self, question: str, context: str) -> str:
        """Build the prompt for the model"""
        if context:
            prompt = f"""Based on the following context, please answer the question comprehensively.

Context: {context}

Question: {question}

Please provide a detailed and accurate answer:"""
        else:
            prompt = f"""Please answer the following question based on your knowledge:

Question: {question}

Please provide a comprehensive and accurate answer:"""
        
        return prompt
    
    def _calculate_confidence(self, answer: str, question: str) -> float:
        """Calculate confidence score (simplified heuristic)"""
        # Simple heuristic based on answer length and keywords
        confidence = 0.5
        
        if len(answer) > 100:
            confidence += 0.2
        
        if len(answer) > 300:
            confidence += 0.1
        
        # Check if answer contains question keywords
        question_words = set(question.lower().split())
        answer_words = set(answer.lower().split())
        overlap = len(question_words.intersection(answer_words))
        
        if overlap > 2:
            confidence += 0.2
        
        return min(confidence, 1.0)
    
    def health_check(self) -> bool:
        """Check if the RAG engine is operational"""
        try:
            # Try a simple prediction
            test_response = self.model.predict(
                "Hello, are you operational?",
                temperature=0.1,
                max_output_tokens=10,
            )
            return len(test_response.text) > 0
        except Exception as e:
            logger.error(f"Health check failed: {str(e)}")
            return False
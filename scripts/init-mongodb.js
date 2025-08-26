// MongoDB initialization script for local development
db = db.getSiblingDB('wizknowledge');

// Create application user
db.createUser({
  user: 'wizapp',
  pwd: 'password123',
  roles: [
    {
      role: 'readWrite',
      db: 'wizknowledge'
    }
  ]
});

// Create collections
db.createCollection('knowledge_base');
db.createCollection('queries');
db.createCollection('test_data');

// Insert sample data
db.test_data.insertMany([
  {
    type: 'security',
    category: 'vulnerability',
    title: 'SQL Injection Prevention',
    content: 'Always use parameterized queries to prevent SQL injection attacks.',
    tags: ['security', 'sql', 'vulnerability'],
    created_at: new Date()
  },
  {
    type: 'security',
    category: 'authentication',
    title: 'Password Security',
    content: 'Use bcrypt or argon2 for password hashing, never store passwords in plain text.',
    tags: ['security', 'authentication', 'passwords'],
    created_at: new Date()
  },
  {
    type: 'development',
    category: 'best-practices',
    title: 'Code Review Guidelines',
    content: 'All code should be reviewed by at least one other developer before merging.',
    tags: ['development', 'process', 'quality'],
    created_at: new Date()
  },
  {
    type: 'sensitive',
    data: 'SSN: 123-45-6789',
    classification: 'PII',
    warning: 'This is test data for security scanning demos'
  },
  {
    type: 'sensitive',
    data: 'Credit Card: 4111-1111-1111-1111',
    classification: 'PCI',
    warning: 'This is test data for security scanning demos'
  }
]);

print('✅ WizKnowledge database initialized with sample data');
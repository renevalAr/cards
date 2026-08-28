#!/bin/bash
# Flashcards Deployment Script for VPS (Ubuntu 22.04/24.04)
# Prerequisites: Docker, Docker Compose, Git

set -e

echo "=== Flashcards Deployment ==="

# 1. Clone or update
if [ -d "flashcards" ]; then
    cd flashcards
    git pull origin main
else
    git clone https://github.com/renevalAr/cards.git flashcards
    cd flashcards
fi

# 2. Create .env if not exists
if [ ! -f backend/.env ]; then
    echo "Creating .env file..."
    cp backend/.env.example backend/.env
    
    # Generate random secret key
    SECRET_KEY=$(openssl rand -hex 32)
    sed -i "s|SECRET_KEY=.*|SECRET_KEY=$SECRET_KEY|" backend/.env
    
    echo "⚠️  Edit backend/.env to configure:"
    echo "   - EMAIL_API_KEY (SendGrid)"
    echo "   - CORS_ORIGINS (your domain)"
    echo "   - ALLOWED_HOSTS (your domain)"
fi

# 3. Build and start
echo "Building and starting containers..."
docker-compose up -d --build

# 4. Wait for database
echo "Waiting for database to be ready..."
for i in {1..30}; do
    if docker-compose exec -T db pg_isready -U flashcards > /dev/null 2>&1; then
        echo "Database is ready!"
        break
    fi
    sleep 2
done

# 5. Run migrations
echo "Running database migrations..."
docker-compose exec backend alembic upgrade head

# 6. Verify health
echo "Checking application health..."
sleep 3
if curl -f http://localhost/api/health > /dev/null 2>&1; then
    echo "✅ Application is healthy!"
else
    echo "❌ Health check failed!"
    docker-compose logs backend
    exit 1
fi

# 7. Run backend tests
echo "Running backend tests..."
docker-compose exec backend pytest tests/ -v --tb=short || true

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "🌐 Application: http://localhost"
echo "📊 Health check: http://localhost/api/health"
echo "📋 API docs: http://localhost/docs (FastAPI Swagger)"
echo ""
echo "Useful commands:"
echo "  docker-compose logs -f       # View logs"
echo "  docker-compose exec backend pytest tests/ -v  # Run tests"
echo "  docker-compose down          # Stop application"
echo "  docker-compose exec db psql -U flashcards -d flashcards  # Database shell"
echo ""
echo "Next steps:"
echo "1. Set up SSL: sudo certbot --nginx -d your-domain.com"
echo "2. Configure firewall: sudo ufw allow 80,443/tcp"
echo "3. Set up automated backups"

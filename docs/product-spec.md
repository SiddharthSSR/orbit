# Orbit Product Spec

## Vision

Orbit is a personal second brain for iPhone. It should collect lightweight personal context, surface what matters today, and eventually let the user ask questions or take action across their own memory.

## Initial Scope

- Todos
- Bills and payment reminders
- Saved links and articles
- Mood check-ins
- Project tracking
- Daily planning
- AI chat over personal memory
- Spotify playlist creation later

## MVP Behavior

The first version focuses on structure:

- Capture memory items into a backend-persistent inbox.
- Store mood check-ins as persistent backend records and let the user submit them from Today.
- Store projects as persistent backend records with status, area, and tags, editable from the Projects tab.
- Show a Today view with plan, mood, and priority tasks.
- Track projects and upcoming bills in dedicated tabs.
- Provide an Ask tab connected to the backend mock AI provider for non-streaming chat over bounded, date-aware Orbit context.

## Non-Goals For Now

- Authentication
- AI summarization and automatic link fetching
- AI coaching or planning personalization
- AI project mentoring
- Real LLM integration, streaming chat, embeddings, and tool execution
- Push notifications
- Spotify integration
- Production AI memory retrieval

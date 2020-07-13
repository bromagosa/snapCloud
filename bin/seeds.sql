-- Simple Seed data for Snap!Cloud.
-- This script should be designed to be re-run as needed!

-- Main snapcloud owner for example collections.
INSERT INTO users (id, username, verified, role)
VALUES (519956, 'snapcloud', true, 'admin')
ON CONFLICT DO NOTHING;

INSERT INTO collections (id, name, creator_id, created_at, updated_at, description, published, published_at, shared, shared_at, thumbnail_id, editor_ids)
VALUES
  (0, 'Flagged', 519956, NOW(), NOW(), '', 'f', NULL, 'f', NULL, NULL, '{}'),
  (4, 'Featured', 519956, NOW(), NOW(), 'This is the collection from which the "Featured Projects" front page carousel feeds.', 't', NOW(), 't', NOW(), NULL, '{}'),
  (6, 'Games', 519956, NOW(), NOW(), 'A collection of games curated by the Snap! team.', 't', NOW(), 't', NOW(), NULL, '{}'),
  (7, 'Fractals', 519956, NOW(), NOW(), 'A collection of fractals curated by the Snap! team.', 't', NOW(),'t', NOW(), NULL, '{}'),
  (8, 'Art Projects', 519956, NOW(), NOW(), 'A collection of art projects curated by the Snap! team.','t', NOW(), 't', NOW(), NULL, '{}'),
  (9, 'Science Projects', 519956, NOW(), NOW(), 'A collection of science-related projects curated by the Snap! team.', 't', NOW(), 't', NOW(), NULL, '{}'),
  (37, 'Animations', 519956, NOW(), NOW(), '', 't', NOW(), 't', NOW(), NULL, '{}'),
  (67, 'Simulations', 519956, NOW(), NOW(), 'Simulating real-world behavior in Snap!.', 'f', NULL, 'f', NULL, NULL, '{}'),
  (390, 'Snap!Con 2019', 519956, NOW(), NOW(), 'Projects that we all demoed, shared or developed during Snap!Con 2019 in Heidelberg.', 't', NOW(), 't', NOW(), NULL, '{}')
 ON CONFLICT DO NOTHING;

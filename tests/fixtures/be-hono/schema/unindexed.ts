import { pgTable, text } from 'drizzle-orm/pg-core';
import { owners } from './owners.ts';

// A foreign key with no index: Postgres does not index a REFERENCES column, so the gate fails.
export const notes = pgTable('notes', {
  id: text('id').primaryKey(),
  authorId: text('author_id')
    .notNull()
    .references(() => owners.id),
  body: text('body').notNull(),
});

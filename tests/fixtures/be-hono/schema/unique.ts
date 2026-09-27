import { pgTable, text } from 'drizzle-orm/pg-core';
import { owners } from './owners.ts';

// A column-level unique constraint is backed by an index, so this foreign key is covered.
export const profiles = pgTable('profiles', {
  id: text('id').primaryKey(),
  ownerId: text('owner_id')
    .notNull()
    .unique()
    .references(() => owners.id),
});

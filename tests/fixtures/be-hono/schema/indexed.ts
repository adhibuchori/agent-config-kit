import { index, pgTable, text, timestamp } from 'drizzle-orm/pg-core';
import { owners } from './owners.ts';

// A foreign key with its index in the same file: the gate passes.
export const things = pgTable(
  'things',
  {
    id: text('id').primaryKey(),
    ownerId: text('owner_id')
      .notNull()
      .references(() => owners.id, { onDelete: 'cascade' }),
    createdAt: timestamp('created_at').notNull().defaultNow(),
  },
  (table) => [index('things_owner_idx').on(table.ownerId)],
);

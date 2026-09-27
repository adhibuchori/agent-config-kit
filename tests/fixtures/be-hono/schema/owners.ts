import { pgTable, text } from 'drizzle-orm/pg-core';

// The referenced table: a primary key only, which Postgres indexes itself.
export const owners = pgTable('owners', {
  id: text('id').primaryKey(),
  name: text('name').notNull(),
});

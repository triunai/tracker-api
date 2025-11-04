create table public.expense_category (
  id bigserial not null,
  name character varying(100) not null,
  description text not null,
  created_by uuid null,
  created_at timestamp without time zone not null default now(),
  updated_by uuid null,
  updated_at timestamp without time zone null,
  isdeleted boolean not null default false,
  constraint expense_category_pkey primary key (id),
  constraint expense_category_name_key unique (name)
) TABLESPACE pg_default;


[
  {
    "id": 1,
    "name": "Groceries",
    "description": "Food and household supplies"
  },
  {
    "id": 2,
    "name": "Eating Out",
    "description": "Meals, cafes, and restaurants"
  },
  {
    "id": 3,
    "name": "Petrol",
    "description": "Fuel and transportation costs"
  },
  {
    "id": 4,
    "name": "Utilities",
    "description": "Electricity, water, gas, internet, etc."
  },
  {
    "id": 5,
    "name": "Entertainment",
    "description": "Movies, concerts, and leisure activities"
  },
  {
    "id": 6,
    "name": "Health",
    "description": "Medical expenses, fitness, and wellbeing"
  },
  {
    "id": 7,
    "name": "Transport",
    "description": "Public transit, taxi, ridesharing"
  },
  {
    "id": 8,
    "name": "Shopping",
    "description": "Clothing, electronics, miscellaneous retail"
  },
  {
    "id": 9,
    "name": "Bills",
    "description": "Recurring monthly bills and subscriptions"
  },
  {
    "id": 10,
    "name": "Education",
    "description": "Tuition, books, courses, and training"
  },
  {
    "id": 11,
    "name": "Travel",
    "description": "Flights, accommodations, and travel-related expenses"
  },
  {
    "id": 12,
    "name": "Gifts",
    "description": "Presents for birthdays, holidays, and special occasions"
  },
  {
    "id": 13,
    "name": "Charity",
    "description": "Donations to non-profits and charitable organizations"
  },
  {
    "id": 14,
    "name": "Home Maintenance",
    "description": "Repairs, renovations, and home improvement costs"
  },
  {
    "id": 15,
    "name": "Insurance",
    "description": "Health, life, auto, and property insurance premiums"
  },
  {
    "id": 16,
    "name": "Pets",
    "description": "Food, vet visits, grooming, and pet supplies"
  },
  {
    "id": 17,
    "name": "Hobbies",
    "description": "Crafts, sports equipment, and recreational activities"
  },
  {
    "id": 18,
    "name": "Childcare",
    "description": "Daycare, babysitters, and educational programs for kids"
  },
  {
    "id": 19,
    "name": "Legal Fees",
    "description": "Lawyer consultations, court fees, and legal documents"
  },
  {
    "id": 20,
    "name": "Investments",
    "description": "Stocks, bonds, mutual funds, and other financial instruments"
  },
  {
    "id": 21,
    "name": "Business Expenses",
    "description": "Office supplies, marketing, and operational costs"
  },
  {
    "id": 22,
    "name": "Fitness Memberships",
    "description": "Gym memberships, yoga classes, and fitness apps"
  },
  {
    "id": 23,
    "name": "Subscriptions",
    "description": "Streaming services, magazines, and software tools"
  },
  {
    "id": 24,
    "name": "Wedding Costs",
    "description": "Venue, catering, attire, and wedding-related expenses"
  },
  {
    "id": 25,
    "name": "Emergency Fund",
    "description": "Unexpected expenses like medical emergencies or repairs"
  },
  {
    "id": 26,
    "name": "Relocation",
    "description": "Moving costs, packing supplies, and temporary housing"
  },
  {
    "id": 27,
    "name": "Taxes",
    "description": "Income tax payments, property taxes, and tax preparation fees"
  },
  {
    "id": 28,
    "name": "Luxury Items",
    "description": "High-end purchases like watches, jewelry, or art"
  },
  {
    "id": 29,
    "name": "Education Supplies",
    "description": "Books, stationery, and school-related materials"
  },
  {
    "id": 30,
    "name": "Digital Services",
    "description": "Cloud storage, web hosting, and online tools"
  },
  {
    "id": 31,
    "name": "test",
    "description": "test checky checky"
  }
]
export type Title = {
  id: string;
  name: string;
  year: number;
  rating: string;
  runtime: string;
  genres: string[];
  description: string;
  image: string;
  accent: string;
  rank?: number;
};

export const catalog: Title[] = [
  {
    id: "last-signal",
    name: "The Last Signal",
    year: 2026,
    rating: "PG-13",
    runtime: "2h 08m",
    genres: ["Sci-Fi", "Drama"],
    description: "A deep-space cartographer follows a transmission that should not exist—and discovers a message sent by her future self.",
    image: "https://images.unsplash.com/photo-1446776811953-b23d57bd21aa?auto=format&fit=crop&w=1800&q=88",
    accent: "#e36f34",
    rank: 1,
  },
  {
    id: "afterlight",
    name: "Afterlight",
    year: 2025,
    rating: "16+",
    runtime: "1h 52m",
    genres: ["Mystery", "Thriller"],
    description: "A photographer finds that every picture she develops shows tomorrow's final hour.",
    image: "https://images.unsplash.com/photo-1519608487953-e999c86e7455?auto=format&fit=crop&w=1200&q=85",
    accent: "#845eff",
    rank: 2,
  },
  {
    id: "velvet-city",
    name: "Velvet City",
    year: 2026,
    rating: "18+",
    runtime: "8 episodes",
    genres: ["Crime", "Drama"],
    description: "Power changes hands after midnight in a city built on beautiful lies.",
    image: "https://images.unsplash.com/photo-1519501025264-65ba15a82390?auto=format&fit=crop&w=1200&q=85",
    accent: "#ef3b63",
    rank: 3,
  },
  {
    id: "wild-current",
    name: "Wild Current",
    year: 2025,
    rating: "PG",
    runtime: "1h 44m",
    genres: ["Adventure", "Family"],
    description: "Two siblings follow a forgotten river into the heart of an impossible forest.",
    image: "https://images.unsplash.com/photo-1433086966358-54859d0ed716?auto=format&fit=crop&w=1200&q=85",
    accent: "#2cbf89",
    rank: 4,
  },
  {
    id: "midnight-line",
    name: "Midnight Line",
    year: 2024,
    rating: "16+",
    runtime: "2h 01m",
    genres: ["Action", "Thriller"],
    description: "The last train out of the city has one passenger who was never meant to board.",
    image: "https://images.unsplash.com/photo-1519608487953-e999c86e7455?auto=format&fit=crop&w=1200&q=85",
    accent: "#2778ff",
    rank: 5,
  },
  {
    id: "house-of-echoes",
    name: "House of Echoes",
    year: 2026,
    rating: "18+",
    runtime: "1h 49m",
    genres: ["Horror", "Mystery"],
    description: "A restoration architect discovers that an abandoned house remembers every family that lived there.",
    image: "https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=1200&q=85",
    accent: "#9f2549",
    rank: 6,
  },
  {
    id: "northbound",
    name: "Northbound",
    year: 2025,
    rating: "PG-13",
    runtime: "6 episodes",
    genres: ["Drama", "Adventure"],
    description: "Five strangers share a winter road and one reason they cannot turn back.",
    image: "https://images.unsplash.com/photo-1483347756197-71ef80e95f73?auto=format&fit=crop&w=1200&q=85",
    accent: "#7ba6c8",
    rank: 7,
  },
  {
    id: "neon-hearts",
    name: "Neon Hearts",
    year: 2024,
    rating: "13+",
    runtime: "1h 38m",
    genres: ["Romance", "Comedy"],
    description: "Two rival DJs discover the perfect mix is easier to find than the perfect relationship.",
    image: "https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&w=1200&q=85",
    accent: "#f044d0",
    rank: 8,
  },
  {
    id: "the-long-table",
    name: "The Long Table",
    year: 2025,
    rating: "PG",
    runtime: "1h 57m",
    genres: ["Comedy", "Drama"],
    description: "One chaotic dinner. Four generations. Every secret on the menu.",
    image: "https://images.unsplash.com/photo-1414235077428-338989a2e8c0?auto=format&fit=crop&w=1200&q=85",
    accent: "#df9a32",
    rank: 9,
  },
  {
    id: "blue-hour",
    name: "Blue Hour",
    year: 2026,
    rating: "PG-13",
    runtime: "10 episodes",
    genres: ["Drama", "Mystery"],
    description: "Every sunrise resets one coastal town—except for the new night-shift doctor.",
    image: "https://images.unsplash.com/photo-1500534314209-a25ddb2bd429?auto=format&fit=crop&w=1200&q=85",
    accent: "#388ed0",
    rank: 10,
  },
];

export const getTitle = (id: string) => catalog.find((title) => title.id === id);

import React from 'react';
import Link from 'next/link';

export default function HomePage() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center p-8 text-center">
      <h1 className="text-4xl font-bold tracking-tight text-gray-900 dark:text-gray-50">
        E2E Test Project
      </h1>
      <p className="mt-4 max-w-md text-gray-600 dark:text-gray-300">
        Demonstrating end-to-end dev-skill execution from greenfield bootstrap to first feature.
      </p>
      <div className="mt-8">
        <Link
          href="/status"
          className="rounded-lg bg-blue-600 px-5 py-2.5 text-sm font-medium text-white shadow transition hover:bg-blue-700 focus:outline-none focus:ring-4 focus:ring-blue-300 dark:bg-blue-500 dark:hover:bg-blue-600"
        >
          View System Status →
        </Link>
      </div>
    </div>
  );
}

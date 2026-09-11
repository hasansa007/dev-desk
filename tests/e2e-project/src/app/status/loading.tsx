import React from 'react';

export default function StatusLoading() {
  return (
    <div className="mx-auto max-w-4xl space-y-6 p-6 animate-pulse">
      <div className="h-24 rounded-xl bg-gray-200 dark:bg-gray-800" />
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <div className="h-28 rounded-xl bg-gray-200 dark:bg-gray-800" />
        <div className="h-28 rounded-xl bg-gray-200 dark:bg-gray-800" />
        <div className="h-28 rounded-xl bg-gray-200 dark:bg-gray-800" />
      </div>
      <div className="h-64 rounded-xl bg-gray-200 dark:bg-gray-800" />
    </div>
  );
}

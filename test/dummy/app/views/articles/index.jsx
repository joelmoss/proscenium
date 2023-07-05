import { lazy, Suspense, useState, useCallback } from "react";
import ReactDOM from "react-dom/client";

const Article = lazy(() => import("./_article"));

const Articles = () => {
  const [isLoaded, setIsLoaded] = useState(false);
  const loadArticle = useCallback(() => {
    setIsLoaded(true);
  }, []);

  return (
    <>
      <h1>Articles</h1>
      <Suspense fallback={<div>loading...</div>}>
        {isLoaded ? (
          <Article />
        ) : (
          <button onClick={loadArticle}>Load Article...</button>
        )}
      </Suspense>
    </>
  );
};

const root = ReactDOM.createRoot(document.getElementById("articles"));

root.render(<Articles />);

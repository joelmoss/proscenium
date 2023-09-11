import styles from "./component.module.css";

const Comp = ({ children }) => {
  return <button className={styles.base}>{children || "Click One!"}</button>;
};

export default Comp;

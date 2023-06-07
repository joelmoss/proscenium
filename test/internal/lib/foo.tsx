import React, { Dispatch, SetStateAction } from 'react'

interface DummyProps {
  number: number
  setNumber: Dispatch<SetStateAction<number>>
}

const DummyComponent:React.FC<DummyProps> = ({ number, setNumber }) => {

  return (
    <>
      <div>{number}</div>

      <button
        onClick={() => setNumber(prev => prev+1)}
      >
        ADD
      </button>
    </>
  )

}

export default DummyComponent
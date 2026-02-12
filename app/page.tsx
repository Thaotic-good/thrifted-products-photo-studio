import Link from "next/link";

export default function Home() {
  return (
    <div>
        <h1>Hello World</h1>
        <p>Lorem ipsum dolor sit amet, consectetur adipisicing elit. At autem eveniet illum iusto nemo odit omnis placeat possimus. Cum dolorem dolores excepturi fuga iste iure iusto nemo provident sequi veritatis?</p>
        <p>Lorem ipsum dolor sit amet, consectetur adipisicing elit. At autem eveniet illum iusto nemo odit omnis placeat possimus. Cum dolorem dolores excepturi fuga iste iure iusto nemo provident sequi veritatis?</p>
<Link href={'/about'}>See about</Link>
    </div>
  );
}

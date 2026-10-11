// Row selector for the review tables. The whole 44px square is the tap target on phones.
export default function RowRadio({
  name,
  checked,
  onChange,
  label,
}: {
  name: string
  checked: boolean
  onChange: () => void
  label: string
}) {
  return (
    <label className="flex size-11 cursor-pointer items-center justify-center lg:size-8">
      <input
        type="radio"
        name={name}
        checked={checked}
        onChange={onChange}
        aria-label={label}
        className="size-5 cursor-pointer accent-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
      />
    </label>
  )
}

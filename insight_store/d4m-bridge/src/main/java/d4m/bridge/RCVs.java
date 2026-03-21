package d4m.bridge;

public class RCVs {

	final String[] rr;
	final String[] cc;
	final String[] vv;
	final String f;
	final String delimiter = ",";

	public RCVs(String[] rr, String[] cc, String[] vv, String f) {
		super();
		this.rr = rr;
		this.cc = cc;
		this.vv = vv;
		this.f = f;
	}

	public String getRr() {
		return String.format("%s%s", String.join(delimiter, rr), delimiter);
	}

	public String getCc() {
		return String.format("%s%s", String.join(delimiter, cc), delimiter);
	}

	public String getVv() {
		return String.format("%s%s", String.join(delimiter, vv), delimiter);
	}

	public String[] getRows() {
		return rr;
	}

	public String[] getCols() {
		return cc;
	}

	public String[] getVals() {
		return vv;
	}

	public String getFamily() {
		return f;
	}

	public String toString() {
		StringBuilder bld = new StringBuilder();
		bld.append(String.join(",", getRr()));
		bld.append(String.join(",", getCc()));
		bld.append(String.join(",", getVv()));
		bld.append(getFamily());
		return bld.toString();
	}

	public int size() {
		return toString().length();
	}
}
